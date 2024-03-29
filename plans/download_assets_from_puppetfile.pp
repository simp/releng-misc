# Download GitHub release attachments from repos specifed in Puppetfile.pinned
#
# @param puppetfile
#   Path or URL to simp-core Puppetfile (e.g., `Puppetfile.pinned`) to identify
#   git repos and release tags
#
# @param targets
#   `github_inventory` Targets that repos with clone_urls that match mods in
#   the Puppetfile
#
# @param target_dir
#   Local directory to download assets into
#
# @param github_api_token
#   GitHub API token.  Doesn't require any scope for public repos.
#
# @param exclude_patterns
#   patterns of filenames to avoid downloading
#
# @param return_result
#    When `true`, plan returns data in a ResultSet
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
  Boolean $return_result  = false,
){
  $puppetfile_mods = run_plan( 'releng::puppetfile_data', {
    'puppetfile' => $puppetfile,
  })

  $puppetfile_repos = run_plan( 'releng::github::puppetfile::repo_targets', {
    'targets' => $targets,
    'pf_mods' => $puppetfile_mods,
  })

  $results = run_plan( 'releng::github::download_release_assets', {
    'targets'          => $puppetfile_repos.values,
    'target_dir'       => $target_dir,
    'exclude_patterns' => $exclude_patterns,
    'github_api_token' => $github_api_token,
  })

  $puppetfile_mods.each |$k,$v| {
    $t = $puppetfile_repos[$k]
    $gh_release_tag = $t.facts.get('_release_data.tag_name').with |$tag_name| {
       $t.facts['_fallback_release_tag'].then |$x| {
         "${tag_name} (fallback)"
       }.lest || {
         $tag_name
       }
    }
    $num_assets = $t.facts.get('_release_data.assets').then |$x| { $x.size }.lest || { '---' }
    $name = $v['repo_name']
    $pf_tag = $v['tag'].lest || { "${v['branch']} (branch)" }
    out::message( "${name},${pf_tag},${gh_release_tag},${num_assets}" )
  }

  if $return_result { return($results) }
}
