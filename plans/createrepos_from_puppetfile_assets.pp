# Download GitHub RPMs for super-release, build repo for each OS
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
# @param return_result
#    When `true`, plan returns data in a ResultSet
#
plan releng::createrepos_from_puppetfile_assets(
  TargetSpec $targets = 'github_repos',
  Variant[Stdlib::HTTPUrl,Stdlib::Absolutepath] $puppetfile = 'https://raw.githubusercontent.com/simp/simp-core/master/Puppetfile.pinned',
  Stdlib::Absolutepath $target_dir = "${system::env('PWD')}/_release_assets",
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_TOKEN')),
  Boolean $return_result  = false,
  Boolean $download_github_assets = true,
){
  $github_repos = get_targets($targets)

  $repos = [
    'el8',
    'el7',
    'el7.src',
    'el8.src'
  ].map |$repo_name| {[
    $repo_name, {
      'path'     => "${target_dir}/${repo_name}",
      'patterns' => $repo_name.split(/\./).map |$x| { ".${x}." },
    }
  ]}.with |$x| { Hash($x) }

  # Download all assets from all repos in Puppetfile.pinned release
  # ----------------------------------------------------------------------------
  if $download_github_assets {
    $download_results = run_plan( 'releng::download_assets_from_puppetfile', {
      'targets'          => $github_repos,
      'puppetfile'       => $puppetfile,
      'target_dir'       => $target_dir,
      'exclude_patterns' => [],
      'github_api_token' => $github_api_token,
    })
  } else {
    log::warn("Skipping releng::download_assets_from_puppetfile because download_github_assets=false")
  }

  # Create local repos
  # ----------------------------------------------------------------------------
  $repos.map |$repo_name, $opts| {
    $ok_files = dir::children($target_dir).filter |$x| {
      '.asc' in $x or $opts.get('patterns').all |$p| {$p in $x}
    }
    [$repo_name, $opts.merge({'files' => $ok_files})]
  }.with |$x| { Hash($x) }.with |$repos| {
    $repos.map |$repo_name, $opts| {
      $t = Target.new($repo_name); $t.add_facts($opts); $t
    }
  }.with |$repo_t| {
    parallelize($repo_t) |$t| {
      # ensure directory
      run_command( "rm -rf '${t.facts['path']}'; mkdir -p '${t.facts['path']}'", $t )

      # copy RPMs for each repo
      $ln_cmds = $t.facts['files'].map |$f| {
        "ln '${target_dir}/${f}' '${t.facts['path']}/${f}'"
      }.join("\n")
      run_command( $ln_cmds, $t )

      # create repos in each dir
      run_command( "createrepo ${t.facts['path']}", $t)
    }
  }
}
