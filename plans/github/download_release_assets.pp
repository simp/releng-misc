# Downloads release assets uploaded to specified GitHub release pages
#
# @param targets
#    By default: `github_repos` group from inventory
#
#    If a target has the fact '_release_tag', that tag will be used to identify
#    the GitHub release to download.  Otherwise, the latest release will be
#    downloaded.
#
#    FIXME it's not yet certain what best course should be when no tag is given; see comments in code
#
# @param target_dir
#    Local directory to download assets into
#
# @param github_api_token
#    GitHub API token.  Doesn't require any scope for public repos.
#
# @param exclude_patterns
#   patterns of filenames to avoid downloading
#
plan releng::github::download_release_assets(
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

  $releases_data = run_plan(
    'releng::github::releases_data',
    $github_repos, {
    'github_api_token' => $github_api_token,
  })


  apply('localhost', '_description' => "Ensure target directory at '${target_dir}'"){
    file{ $target_dir: ensure => directory }
  }

  $localhost = get_target('localhost')

  # ============================================================================
  # For each release, download all assets (except for filtered-out assets)
  # ============================================================================
  $release_download_results = $releases_data.map |$repo_name, $release_data| {

    # Skip repo if we don't have release data for it
    # --------------------------------------------------------------------------
    if $release_data =~ Undef {
       $expected_tag = $github_repos.filter |$t| { $t.name == $repo_name }[0].then |$t| {
         $t.facts['_release_tag']
       }.lest || { '???' }
       $expected_relpage = $github_repos.filter |$t| { $t.name == $repo_name }[0].then |$t| {
         $t.facts['html_url'].then |$x| { "$x/releases" }
       }.lest || { '???' }

       $err = "Expected ${repo_name} release with tag '${expected_tag}' but couldn't find it!"
       log::error( "UNEXPECTED ERROR: $err")
       $msg = "SKIPPING ${repo_name}: $err"
       log::warn( "  >> ${msg}" )
       ctrl::sleep(3)

       next([
         $repo_name,
         Result.new($localhost, { 'status' => 'skipped',  'skipped?' => $msg })
       ])
    }

    out::message("== $repo_name (Release: ${release_data['tag_name']})")
    out::verbose("  -- Release page: ${release_data['html_url']}")

    # Download repo's assets
    # --------------------------------------------------------------------------
    $asset_dl_results = $release_data['assets'].map |$asset| {

      # Reject downloading files that match exclude patterns
      # ------------------------------------------------------------------------
      if ($exclude_patterns.any |$substr| { $asset['name'] =~ $substr }) {
        $msg = "SKIPPING ${asset['name']} because it matched exclude_patterns"
        log::warn( "  -- ${msg}" )
        next([
          $asset['name'],
          Result.new($localhost, { 'status' => 'skipped',  'skipped?' => $msg })
        ])
      }

      # Download asset files
      # ------------------------------------------------------------------------
      out::message("  -- Asset: ${asset['name']}")
      log::info("  -- Asset URL: ${asset['browser_download_url']}")

      $dl_result = run_command(
        "curl -o '${target_dir}/${asset['name']}' -sS -L -H '${asset['content']}' '${asset['browser_download_url']}'",
        $localhost,
        "Download ${asset['browser_download_url']}"
      )
      [ $asset['name'], $dl_result ]
    }.with |$kv_pairs| { Hash($kv_pairs) }
    [$repo_name, $asset_dl_results]
  }.with |$kv_pairs| { Hash($kv_pairs) }

  # Review issues with targets
  # ----------------------------------------------------------------------------
  $repos_without_release_assets_fact = $github_repos.filter |$t| { !$t.facts.get('_release_assets') }
  $repos_without_release_assets = ($github_repos - $repos_without_release_assets_fact).filter |$t| {
    $t.facts.get('_release_assets').lest || {[]}.empty
  }
  $repos_with_few_release_assets = ($github_repos - $repos_without_release_assets).filter |$t| {
    $t.facts.get('_release_assets').lest || {[]}.size < $min_expected_assets
  }

  # ============================================================================
  # Report what happened!
  # ============================================================================
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
