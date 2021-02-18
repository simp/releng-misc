# @private true
plan releng::gitlab_project__matching_github_repos_facts (
  TargetSpec $targets = 'gitlab_projects',
  TargetSpec $gh_targets = 'github_orgs',
  Sensitive[String[1]] $gitlab_api_token = Sensitive.new(system::env('GITLAB_API_PRIVATE_TOKEN')),
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_INTEGRATION_TOKEN')),
  Boolean              $remove_unmatched = false,
){
  $gitlab_projects = get_targets($targets)
  $github_repos = get_targets($gh_targets)

  $result_targets = $gitlab_projects.map |$t| {
    $gh_repo = $github_repos.filter |$r| {
      $r.name.split('/')[-1] == $t.name.split('/')[-1]
    }.with |$repos| { if $repos.empty {
        warning( "WARNING: No matching GitHub repo found for GitLab project '${t.name}'!" )
        undef
      } else {
        $repos[0].facts
      }
    }
    $t.add_facts( { 'gl_matching_gh_repo' => $gh_repo } )
  }.filter |$t| {
    ( $remove_unmatched and $t.facts['gl_matching_gh_repo'] =~ Undef ) ? {
      true => false,
      default => true,
    }
  }

  return($result_targets)
}
