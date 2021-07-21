# Downloads release asset uploaded to specific GitHub release pages
#
# @param targets
#    By default: `github_repos` group from inventory
#
#    If a target has the var 'release_tag', that tag will be used to identify
#    the release to download.  Otherwise, the latest release will be downloaded.
#
# @param target_dir
#    Local directory to download assets into
#
plan releng::github_download_release_assets(
  TargetSpec $targets = 'github_repos',
  Stdlib::Absolutepath $target_dir = "${system::env('PWD')}/_release_assets",
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_TOKEN')),
  Array[String[1]] $exclude_patterns = [
    '\.src.*\.rpm$'
  ]
){
  $github_repos = get_targets($targets)

  $releases_resultset = run_task_with(
    'http_request', $github_repos, "Get GitHub releases data for all repo targets"
  ) |$repo_target| {
    {
      # Q: look up release by tag for each target and pass it into URI template here?
      # A: Probably no need; this method works with ~100 fewer API calls
      'base_url' => $repo_target.facts['releases_url'].releng::expand_uri( {} ),
      'method'   => 'get',
      'headers' => {
        'Accept'        => 'application/vnd.github.v3+json',
        'Authorization' => "token ${github_api_token.unwrap}",
      },
      'json_endpoint' => true
    }
  }

  $release_assets = Hash( $releases_resultset.ok_set.map |$result| {
    $rel_data = $result.value['body'].filter |$rel| {
      !$rel['draft'] and !$rel['prerelease']
    }.with |$rels| {
      $result.target.facts['_release_tag'].then |$rel_tag| {
        $rels.filter |$rel| { $rel['tag_name'] == $rel_tag }.then |$x| { $x[0] }.lest || {
          $msg = "ERROR: Expected ${result.target.name} release with tag '${rel_tag}' but couldn't find it!"
          log::error($msg)
          # fail_plan($msg) # TODO We should probably fail in this case
                            # unless we are using the plan to identify missing releases/RPMs
          false # TODO or we could gather all the not-founds and report them in later in a collective failure`
          # FIXME second option is better; we need to identify repos without release assets

        }
      }.lest || {
        # FIXME : when no release_tag is given, should we:
        #    - fail
        #    - take the latest tag
        #    - take the latest tag along the default branch
        #    - take the latest tag along the tracking branch if we know it
        #    - something fancier (tag version/range validation, etc)
        #
        # ^^ When answered: should/which of these behaviors should be determined by plan parameters?
        $rels[0]  # take the first result (most recent) # FIXME not necessarily what we want; see above
      }
    }.with |$rel| {
      if $rel {
        $rel.filter |$key,$v| { $key in ['assets', 'id','tag_name','assets', 'url', 'html_url'] }
      }
    }
    [$result.target.name, $rel_data]
  })

  apply('localhost', '_description' => "Ensure target directory at '${target_dir}'"){
    file{ $target_dir: ensure => directory }
  }

  # For each release download each asset (filter on/out el7? el8? src?)
  $release_download_results = $release_assets.map |$repo_name, $release| {
    if $release =~ Undef {
       $expected_tag = $github_repos.filter |$t| { $t.name == $repo_name }[0].then |$t| {
         $t.facts['_release_tag']
       }.lest || { '???' }
       $expected_relpage = $github_repos.filter |$t| { $t.name == $repo_name }[0].then |$t| {
         $t.facts['html_url'].then |$x| { "$x/releases" }
       }.lest || { '???' }
       $err = "Expected ${repo_name} release with tag '${expected_tag}' but couldn't find it!"
       log::error( "UNEXPECTED ERROR: $err\nFind out why!" )
       out::message( " - Releases page: ${expected_relpage}" )
        debug::break()
        # TODO what should we do when this happens?
        $msg = "SKIPPING ${repo_name}: $err"
        log::warn( "  -- ${msg}" )
        next([
          $repo_name,
          Result.new(get_target('localhost'), { 'status' => 'skipped',  'skipped?' => $msg })
        ])
    }
    out::message("== $repo_name (Release: ${release['tag_name']})")
    out::verbose("  -- Release page: ${release['html_url']}")
    $assets = $release['assets']
    $asset_dl_results = $assets.map |$asset| {
      out::message("  -- Asset: ${asset['name']}")

      # Reject downloading some files based on exclude patterns
      if ($exclude_patterns.any |$substr| { $asset['name'] =~ $substr }) {
        $msg = "SKIPPING ${asset['name']} because it matched exclude_patterns"
        log::warn( "  -- ${msg}" )
        next([
          $asset['name'],
          Result.new(get_target('localhost'), { 'status' => 'skipped',  'skipped?' => $msg })
        ])
      }
      log::info("  -- Asset URL: ${asset['browser_download_url']}")

      $dl_result = run_command(
        "curl -o '${target_dir}/${asset['name']}' -sS -L -H '${asset['content']}' '${asset['browser_download_url']}'",
        'localhost',
        "Download ${asset['browser_download_url']}"
      )
      [ $asset['name'], $dl_result ]
    }.with |$kv_pairs| { Hash($kv_pairs) }
    [$repo_name, $asset_dl_results]
  }.with |$kv_pairs| { Hash($kv_pairs) }

  return($release_download_results)
}
