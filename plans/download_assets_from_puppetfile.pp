# Download GitHub release attachments from repos specifed in Puppetfile.pinned
#
# @param puppetfile
#    Path or URL to simp-core Puppetfile (e.g., `Puppetfile.pinned`) to identify
#    git repos and release tags
#
# @param targets
#    `github_inventory` Targets that repos with clone_urls that match mods in
#    the Puppetfile
#
# @param target_dir
#    Local directory to download assets into
#
# @param github_api_token
#    GitHub API token.  Doesn't require any scope for public repos.
#
plan releng::download_assets_from_puppetfile(
  TargetSpec $targets = 'github_repos',
  Variant[Stdlib::HTTPUrl,Stdlib::Absolutepath] $puppetfile = 'https://raw.githubusercontent.com/simp/simp-core/master/Puppetfile.pinned',
  Stdlib::Absolutepath $target_dir = "${system::env('PWD')}/_release_assets",
  Array[String[1]] $exclude_patterns = [
    '\.src.*\.rpm$',
    '\.el7.*\.rpm$',
  ],
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_TOKEN')),
){
  $pf_mods = run_plan( 'releng::puppetfile::data', {
    'puppetfile' => $puppetfile,
  })

  $matched_pf_mods = run_plan( 'releng::puppetfile::github::repo_targets', {
    'targets' => $targets,
    'pf_mods' => $pf_mods,
  })

  $results = run_plan( 'releng::github_download_release_assets', {
    'targets'          => $matched_pf_mods.values,
    'target_dir'       => $target_dir,
    'exclude_patterns' => $exclude_patterns,
    'github_api_token' => $github_api_token,
  })

  $pf_mods.each |$k,$v| {
    $t = $matched_pf_mods[$k]
    # $t.facts['_fallback_release_tag']
    # $t.facts['_release_tag']
    # $t.facts['_tracking_branch']
    # $t.facts['_release_assets'].size
    $gh_release_tag = $t.facts['_release_tag'].lest || {
      $t.facts['_fallback_release_tag'].then |$x| { "${x} (fallback)" }
    }
    $num_assets = $t.facts['_release_assets'].then |$x| { $x.size }.lest || { '---' }
    $name = $v['repo_name']
    $pf_tag = $v['tag'].lest || { "${v['branch']} (branch)" }
    out::message( "${name},${pf_tag},${gh_release_tag},${num_assets}" )
  }
  debug::break()
  return($results)
}
