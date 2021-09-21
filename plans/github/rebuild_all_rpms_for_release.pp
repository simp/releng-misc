# Trigger GitHub Actions to rebuild all RPMs attached to components' release pages
#
# @param puppetfile
#   URL to Puppetfile containing the individual components and release versions
#   to rebuild
# @param trigger_repo
#   GitHub repo containing the release_rpms workflow that will rebuild the
#   other repos' RPMs
#
# @param trigger_org  GitHub org for `$trigger_repo`
# @param trigger_ref  GitHub ref of release_rpms workflow in `$trigger_repo`
# @param skip_repos   List of Puppetfile repos to ignore
#
# @param targets The targets to run on.
plan releng::github::rebuild_all_rpms_for_release (
  TargetSpec $targets = 'github_repos',
  Variant[Stdlib::HTTPUrl,Stdlib::Absolutepath] $puppetfile = 'https://raw.githubusercontent.com/simp/simp-core/master/Puppetfile.pinned',
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_TOKEN')),
  String[1] $trigger_org                 = 'simp',
  String[1] $trigger_repo                = 'pupmod-simp-mockup',
  String[1] $trigger_ref                 = 'master',
  Array[String[1]] $skip_repos           = ['simp-doc']
) {
  # Read all `mod` items from Puppetfile
  $pf_mods = run_plan('releng::puppetfile_data', {'puppetfile' => $puppetfile})

  # Get path => repo Hash of github_inventory Targets for each Puppetfile `mod`
  $github_repos = run_plan(
    'releng::github::puppetfile::repo_targets', $targets, { 'pf_mods' => $pf_mods }
  ).with |$puppetfile_repos| {
    $puppetfile_repos.values
  }

  $releases_data = run_plan(
    'releng::github::releases_data',
    $github_repos, {
    'github_api_token' => $github_api_token,
  })

  $trigger_results = $github_repos.map |$repo| {
    if $repo.name in $skip_repos {
      log::warn("WARNING: SKIPPING RPM build triggers for ${repo.name}, because it's a skip repo")
      next(Result.new( $repo, {'extra' => {'skipped?' => 'repo marked as noop' }}))
    }

    $tag = $repo.facts['_release_tag'].lest || {$repo.facts['_fallback_release_tag']}
    $args = {
      'target_repo'              => $repo.name,
      'release_tag'              => $tag,
      'build_container_os'       => 'centos8',
      'clobber_identical_assets' => true,
      'wipe_all_assets_first'    => true,
      'autocreate_release'       => true,
      'trigger_repo'             => $trigger_repo,
      'trigger_org'              => $trigger_org,
      'trigger_ref'              => $trigger_ref,
      'github_api_token'         => $github_api_token,
    }
    out::message('')
    out::message("======= Rebuilding RPMs for ${repo.name} ${tag} on centos8:")
    $trigger_result1 = run_plan('releng::github::workflow::release_rpms', $github_repos, $args)

    ctrl::sleep(60)
    out::message("------- Rebuilding RPMs for ${repo.name} ${tag} on centos7:")
    $trigger_result2 = run_plan('releng::github::workflow::release_rpms', $github_repos, $args + {
      'build_container_os'       => 'centos7',
      'wipe_all_assets_first'    => false,
      'clobber_identical_assets' => false,
    })
  }

  out::message("FINIS")
  debug::break()
  $rebuild_results
}
