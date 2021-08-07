# Trigger `release_rpms.yml` workflow
#
# @param targets
#    `github_inventory` Targets with clone_urls expected to match the
#    Puppetfile mod' :git urls
#
# @param github_api_token
#    GitHub API token.  Doesn't require any scope for public repos.
#
#  #        release_tag:
#        description: "Release tag"
#        required: true
#      clobber:
#        description: "Clobber identical assets?"
#        required: false
#        default: 'yes'
#      clean:
#        description: "Wipe all release assets first?"
#        required: false
#        default: 'no'
#      autocreate_release:
#        # A GitHub release is needed to upload artifacts to, and some repos
#        # (e.g., forked mirrors) only have tags.
#        description: "Create release if missing? (tag must exist)"
#        required: false
#        default: 'yes'
#      build_container_os:
#        description: "Build container OS"
#        required: true
#        default: 'centos8'
#      target_repo:
#        description: "Target repo (instead of this one)"
#        required: false
#      # WARNING: To avoid exposing secrets in the log, only use this token with
#      #          action/script's `github-token` parameter, NEVER in `env:` vars
#      target_repo_token:
#        description: "API token for uploading to target repo"
#        required: false
#      dry_run:
#        description: "Dry run (Test-build RPMs)"
#        required: false
#        default: 'no'
plan releng::github::release_rpms_workflow(
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
      true    => $inputs + { 'target_repo' => $target_repo },
      default => $inputs,
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

