# Downloads release asset uploaded to specific GitHub release pages
#
# @param targets
#    By default: `github_repos` group from inventory
#
#    If a target has the fact '_release_tag', that tag will be used to identify
#    the GitHub release to download.  Otherwise, the latest release will be downloaded.
#    FIXME it's not yet certain what best course should be when no tag is given; see comments in code
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
  ],
  Boolean $branches_fall_back_to_latest_release = true,
  Integer[0] $min_expected_assets = 2,
  Boolean $debug_problems = false,
){
  $github_repos = get_targets($targets)

  $releases_resultset = run_task_with(
    'http_request', $github_repos, "Get GitHub releases data for all repo targets"
  ) |$repo_target| {
    {
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
      # keep !$rel['prerelease'], because we only grab when the pupmod has a branch instead of tag
      !$rel['draft']
    }.with |$rels| {
      $result.target.facts['_release_tag'].then |$rel_tag| {
        $rels.filter |$rel| { $rel['tag_name'] == $rel_tag }.then |$x| { $x[0] }.lest || {
          $msg = "ERROR: Expected ${result.target.name} release with tag '${rel_tag}' but couldn't find it!"
          log::error($msg)
          false
        }
      }.lest || {
        # FIXME : when no release_tag is given, should we:
        #    - fail
        #    - take the latest release tag along the tracking branch (we may not know it)
        #    - take the latest release tag along the default branch
        #    - take the latest release tag, period
        #    - do something fancy (tag version/range validation, etc)
        #
        # ^^ When answered: should/which of these behaviors should be determined by plan parameters?

        $t = $result.target
        $t.facts.get('_tracking_branch').then |$branch| {
          if $branches_fall_back_to_latest_release {
            log::error("${t.name} specifies no release tag")
            # TODO this should probably find the latest release along the tracking branch
            $fallback_tag = $rels[0].get('tag_name')
            $result.target.add_facts({'_fallback_release_tag' => $fallback_tag})
            log::warn("${t.name} uses tracking branch '${branch}'; falling back to latest tag '${fallback_tag}'")
            $rels[0]  # take the first result (most recent release) # FIXME not necessarily what we want; see above
          }
        }.lest || {
          $msg = "ERROR: ${t.name} has NO release tag or tracking branch!"
          log::error($msg)
          ## debug::break()
          ## fail_plan($error)
        }
      }
    }.with |$rel| {
      if $rel {
        $rel.filter |$key,$v| { $key in ['assets', 'id','tag_name','assets', 'url', 'html_url'] }
      }
    }

    if $rel_data { $result.target.add_facts({'_release_assets' => $rel_data['assets']}) }

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

       # TODO optionally skip and report repos without releases
       $err = "Expected ${repo_name} release with tag '${expected_tag}' but couldn't find it!"
       log::error( "UNEXPECTED ERROR: $err")
       $msg = "SKIPPING ${repo_name}: $err"
       log::warn( "  >> ${msg}" )
       ctrl::sleep(3)
       next([
         $repo_name,
         Result.new(get_target('localhost'), { 'status' => 'skipped',  'skipped?' => $msg })
       ])
    }
    out::message("== $repo_name (Release: ${release['tag_name']})")
    out::verbose("  -- Release page: ${release['html_url']}")
    $assets = $release['assets']
    $asset_dl_results = $assets.map |$asset| {

      # Reject downloading some files based on exclude patterns
      if ($exclude_patterns.any |$substr| { $asset['name'] =~ $substr }) {
        $msg = "SKIPPING ${asset['name']} because it matched exclude_patterns"
        log::warn( "  -- ${msg}" )
        next([
          $asset['name'],
          Result.new(get_target('localhost'), { 'status' => 'skipped',  'skipped?' => $msg })
        ])
      }
      out::message("  -- Asset: ${asset['name']}")
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

  # Review issues with targets
  $repos_without_release_assets_fact = $github_repos.filter |$t| { !$t.facts.get('_release_assets') }
  $repos_without_release_assets = ($github_repos - $repos_without_release_assets_fact).filter |$t| {
    $t.facts.get('_release_assets').lest || {[]}.empty
  }
  $repos_with_few_release_assets = ($github_repos - $repos_without_release_assets).filter |$t| {
    $t.facts.get('_release_assets').lest || {[]}.size < $min_expected_assets
  }

  if $repos_without_release_assets_fact.size > 0 {
    log::error("??ERROR??: Found ${repos_without_release_assets_fact.size} repos did not resolve a _release_assets fact")
    $repos_without_release_assets_fact.each |$t| {
      $err = @("NO_RELEASE_ASSETS_TAG_MSG")
         - ${t.name}
         _release_tag: ${t.facts.get('_release_tag').lest || {'???'}}
         url: ${t.facts['html_url'].then |$x| { "$x/releases" }}")
      | NO_RELEASE_ASSETS_TAG_MSG
      log::warn( $err )
    }
    if $debug_problems { debug::break() }
  }

  if (!$repos_without_release_assets.empty) {
    log::error("ERROR: Found ${repos_without_release_assets} repos with NO release assets")
    $repos_without_release_assets.each |$t| {
      $err = @("NO_RELEASE_ASSETS_MSG")
         - ${t.name}
         _release_tag: ${t.facts.get('_release_tag').lest || {'???'}}
         url: ${t.facts['html_url'].then |$x| { "$x/releases" }}")
      | NO_RELEASE_ASSETS_MSG
      log::warn($err)
    }
    if $debug_problems { debug::break() }
  }

  if (!$repos_with_few_release_assets.empty) {
    log::error("ERROR: Found ${repos_with_few_release_assets.size} repos with fewer release assets than expected ${min_expected_assets}")
    $repos_with_few_release_assets.each |$t| {
      $asset_names = $t.facts.get('_release_assets').lest || {[]}.map |$a| { $a['name'] }
      log::warn( "ERROR: Release assets for ${t.name} = ${asset_names}; less than expected (${min_expected_assets})")
    }
    if $debug_problems { debug::break() }
  }

  return($release_download_results)
}
