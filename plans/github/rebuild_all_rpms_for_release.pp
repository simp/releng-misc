# This is the structure of a simple plan. To learn more about writing
# Puppet plans, see the documentation: http://pup.pt/bolt-puppet-plans

# The summary sets the description of the plan that will appear
# in 'bolt plan show' output. Bolt uses puppet-strings to parse the
# summary and parameters from the plan.
# @summary A plan created with bolt plan new.
# @param targets The targets to run on.
plan releng::github::rebuild_all_rpms_for_release (
  TargetSpec $targets = 'github_repos',
  Variant[Stdlib::HTTPUrl,Stdlib::Absolutepath] $puppetfile = 'https://raw.githubusercontent.com/simp/simp-core/master/Puppetfile.pinned',
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_TOKEN')),
  String[1] $trigger_org                 = 'simp',
  String[1] $trigger_repo                = 'pupmod-simp-mockup',
  String[1] $trigger_ref                 = 'master',
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
    $skip_repo = 'simp/simp-doc'
    if $skip_repo == $repo.facts['full_name'] {
      log::warn("=== SKIPPING trigger for ${skip_repo} because it's the skip repo")
      next(Result.new( $repo, {'extra' => {'skipped?' => 'repo marked as noop' }}))
    }

    $rebuild_results = $github_repos.map |$t| {
      $tag = $t.facts['_release_tag'].lest || {$t.facts['_fallback_release_tag']}
      $args = {
        'target_repo'              => $t.name,
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
      out::message("======= Rebuilding ${t.name} ${tag} on centos8:")
      $trigger_result1 = run_plan('releng::github::workflow::release_rpms', $github_repos, $args)

      out::message("------- Rebuilding ${t.name} ${tag} on centos7:")
      $trigger_result2 = run_plan('releng::github::workflow::release_rpms', $github_repos, $args + {
        'build_container_os' => 'centos7',
        'wipe_all_assets_first'    => false,
        'clobber_identical_assets' => false,
      })
      ctrl::sleep(120)
    }
  }

  out::message("FINIS")
  debug::break()
  $rebuild_results
}
