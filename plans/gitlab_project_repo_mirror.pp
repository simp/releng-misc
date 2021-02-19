# Mirror (or re-mirror) all GitLab projects to their corresponding GitHub repo
#
# Targets are defined by inventory.yaml
#
# @param targets
#    By default: `gitlab_projects` group from inventory
#
# @param gh_targets
#   By default: `github_orgs` group from inventory
#
# @param gitlab_api_token
#   The Gitlab API token that will status/configure GitLab projects
#   (needs `read-write-api` scope)
#
# @param ignore_list
#    List of project names to ignore, as Strings or Patterns
#
#        Note that it's more efficient (and API-friendly) to do this from the
#        inventory.yaml, using the gitlab_inventory plugin's `block_list`
#
# @param include_list
#    List of project names to include, as Strings or Patterns.
#
#        Note that it's more efficient (and API-friendly) to do this from the
#        inventory.yaml, using the gitlab_inventory plugin's `allow_list`
plan releng::gitlab_project_repo_mirror(
  TargetSpec $targets = 'gitlab_projects',
  TargetSpec $gh_targets = 'github_repos',
  Sensitive[String[1]] $gitlab_api_token = Sensitive.new(system::env('GITLAB_API_PRIVATE_TOKEN')),
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_INTEGRATION_TOKEN')),
  Boolean $noop = false,
  Boolean $force = false,
  Optional[[Array[Variant[String,Regexp]]]] $ignore_list = [ /gitlab-oss/ ],
  Optional[[Array[Variant[String,Regexp]]]] $include_list = [],
){

  # Filtered Targets, with the 'gl_project_github_service' fact added
  $gitlab_projects = run_plan(
    'releng::gitlab_project__filter',
    {
      'targets'      => $targets,
      'ignore_list'  => $ignore_list,
      'include_list' => $include_list,
    }
  ).with |$gitlab_targets| {
    run_plan(
      'releng::gitlab_project__matching_github_repos_facts',
      {
        'targets'          => $gitlab_targets,
        'gh_targets'       => $gh_targets,
        'gitlab_api_token' => $gitlab_api_token,
        'github_api_token' => $github_api_token,
        'remove_unmatched' => false,
      }
    )
  }
  $gitlab_projects_by_name = Hash($gitlab_projects.map |$t| { [$t.name, $t ] })

  $mirror_settings = {
    'mirror'                              => true,
    'only_mirror_protected_branches'      => false,
    'mirror_trigger_builds'               => false,
    'mirror_overwrites_diverged_branches' => true,
  }

  # TODO: determine that mirror-worthy github repo actually exists

  unless $noop {
    # Set the mirror for GitLab projects that have matching GitHub repos
    # ------------------------------------------------------------------------------
    $gl_project_repo_mirrors = run_task_with(
      'http_request',
      $gitlab_projects.filter |$t| { $t.facts['gl_matching_gh_repo'] =~ Hash },
      "Get projects' repo mirrors",
      { '_catch_errors' => true } # FIXME should this really be true?
    ) |$t| {
      {
        'base_url' => "${t.facts['_links']['self']}", # Ex: https://gitlab.com/api/v4/projects/3330676
        'method'   => 'put',
        'headers'  => { 'Authorization' => "Bearer ${gitlab_api_token.unwrap}" },
        'json_endpoint' => true,
        'body' => $mirror_settings + { 'import_url' => $t.facts['gl_matching_gh_repo']['clone_url'] },
      }
    }

    $gl_project_repo_mirrors_push_targets = $gl_project_repo_mirrors.filter |$r| {
      $r.value['status_code'] == 200
    }.map |$r| { $r.target }

    $gl_project_repo_mirrors_push = run_task_with(
      'http_request',
      $gl_project_repo_mirrors_push_targets,
      "Start pull mirroring process for projects' repo mirrors",
      { '_catch_errors' => true } # FIXME should this really be true?
    ) |$t| {
      {
        'base_url' => "${t.facts['_links']['self']}/", # Ex: https://gitlab.com/api/v4/projects/3330676
        'path'     => 'mirror/pull',
        'method'   => 'post',
        'headers'  => { 'Authorization' => "Bearer ${gitlab_api_token.unwrap}" },
        'json_endpoint' => true,
      }
    }
  }

  out::message(format::table({
    title => 'Results',
    head  => ['Project', 'Old Mirror User ID', 'New Mirror User ID', 'Start Pull status'],
    rows  => $gl_project_repo_mirrors.map |$r| {
      unless $r.value['status_code'] == 200 {
        [$r.target.name, "${r.target.facts['mirror_user_id']}", format::colorize( "${r.value['body']['message']}", 'red' ), '']
      } else {[
        $r.target.name,
        "${r.target.facts['mirror_user_id']}",
        "${r.value['body']['mirror_user_id']}",
        "${gl_project_repo_mirrors_push.results.filter |$r2| {
           $r2.target.name == $r.target.name
        }[0].value['status_code']}"
      ]}
    }
  }))

  out::message( [
    "Repos: ${gitlab_projects.size}",
    "Mirrored Repos (200):   ${gl_project_repo_mirrors.filter |$r| { $r.value['status_code'] == 200 }.size }",
    "Mirrored? Repos (!200): ${gl_project_repo_mirrors.filter |$r| { $r.value['status_code'] != 200 }.size }",
    "Repos without a GitHub match: ${gitlab_projects.filter |$t| { $t.facts['gl_matching_gh_repo'] =~ Undef }.size}",
    ].join("\n")
  )

  if $gitlab_projects.filter |$t| { $t.facts['gl_matching_gh_repo'] =~ Undef }.size > 0 {
    out::message(format::table({
      title => 'GitLab Projects without matching GitHub Repos',
      head  => ['Project'],
      rows  => $gitlab_projects.filter |$t| { $t.facts['gl_matching_gh_repo'] =~ Undef }.map |$t| { [$t.name] }
    }))
  }
}
