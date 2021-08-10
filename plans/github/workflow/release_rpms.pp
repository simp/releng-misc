# Trigger `release_rpms.yml` workflow for a single repo
#
# @param trigger_org
#   Org for `trigger_repo`
#
# @param trigger_repo
#   Repo used to run the workflow (e.g., `pupmod-simp-mockup`)
#   Also the target repo to release unless `target_repo` is set
#
# @param trigger_ref
#   Ref in `trigger_repo` from which to run the workflow
#
# @param github_api_token
#    GitHub API token, with scope that can run workflows and upload attachments
#
# @param release_tag
#   Release tag (e.g., `1.2.3`, `1.2.3-pre1`, 'v1.2.3` (mirrored forks))
#
# @param clobber_identical_assets
#   Clobber identical assets?
#
# @param wipe_all_assets_first
#   Wipe all release assets first?
#
# @param autocreate_release
#   Create release if missing? Note: the `release_tag` must already exist
#
# @param build_container_os
#   SIMP Build Container OS to build RPMs (e.g., `centos8`, `centos7`)
#
# @param target_repo
#   Target repo (if targeting repo other than the trigger repo)
#
# @param dry_run
#   Dry run (Test-build RPMs, but do not attach to GitHub release)
#
# @param targets
#   Mandatory plan parameter, has no effect
#   (The API http_request task is always run from `localhost`)
#
plan releng::github::workflow::release_rpms(
  TargetSpec $targets                    = 'localhost',
  String[1] $release_tag,
  Boolean $clobber_identical_assets      = true,
  Boolean $wipe_all_assets_first         = false,
  Boolean $autocreate_release            = true,
  String[1] $build_container_os          = 'centos8',
  Optional[String[1]] $target_repo       = undef,
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_TOKEN')),
  String[1] $trigger_org                 = 'simp',
  String[1] $trigger_repo                = 'pupmod-simp-mockup',
  String[1] $trigger_ref                 = 'master',
  Boolean $dry_run                       = false,

){

  $workflow = 'release_rpms.yml'
  $url = "https://api.github.com/repos/${trigger_org}/${trigger_repo}/actions/workflows/${workflow}/dispatches"

  $inputs = {
    'release_tag'        => $release_tag,
    'clobber'            => $clobber_identical_assets ? { true => 'yes', default => 'no' },
    'clean'              => $wipe_all_assets_first ? { true => 'yes', default => 'no' },
    'autocreate_release' => $autocreate_release ? { true => 'yes', default => 'no' },
    'build_container_os' => $build_container_os,
    'dry_run'            => $dry_run ? { true => 'yes', default => 'no' },
  }.with |$inputs| {
    $target_repo ? {
      NotUndef => $inputs + { 'target_repo' => $target_repo },
      default  => $inputs,
    }
  }

  $body = {
    'ref' => $trigger_ref,
    'inputs' => ($inputs + { 'target_repo_token' => $github_api_token.unwrap }),
  }
  $r = run_task_with(
    'http_request', 'localhost', 'Trigger release_rpms.yml Github workflow',
  ) |$repo_target| {
    {
      'base_url' => $url,
      'method'   => 'post',
      'headers' => {
        'Accept'        => 'application/vnd.github.v3+json',
        'Authorization' => "token ${github_api_token.unwrap}",
      },
      'body' => $body,
      'json_endpoint' => true,
    }
  }
  unless($r.ok){
    out::error( $r[0].to_yaml )
  }

  return( $r )
}

