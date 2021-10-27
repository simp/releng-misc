# Find the headmost release (with the closest commit to HEAD) along the tracking branch
plan releng::github::headmost_release_on_tracking_branch (
  TargetSpec $targets,
  String[1] $branch,
  # FIXME: add prerelease logic
  Boolean $include_prereleases = true,
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_TOKEN')),
){
  $github_repo = get_target($targets)


  $tags_resultset = run_task_with(
    'http_request', $github_repo, "Get GitHub tags data for ${github_repo.name}",
  ) |$repo_target| {
    {
      'base_url' => $github_repo.facts['tags_url'],
      'method'   => 'get',
      'headers' => {
        'Accept'        => 'application/vnd.github.v3+json',
        'Authorization' => "token ${github_api_token.unwrap}",
      },
      'json_endpoint' => true
    }
  }

  $n_tags = $tags_resultset[0].value['body'].map|$t| {
    [$t['name'], $t['commit']]
  }.with |$x| { Hash.new($x) }

  $releases = run_task_with(
    'http_request', $github_repo, "Get GitHub releases data for ${github_repo.name}",
  ) |$repo_target| {
    {
      'base_url' => $github_repo.facts['releases_url'].releng::expand_uri( {} ),
      'method'   => 'get',
      'headers' => {
        'Accept'        => 'application/vnd.github.v3+json',
        'Authorization' => "token ${github_api_token.unwrap}",
      },
      'json_endpoint' => true
    }
  }[0].value['body'].map |$release| {
    $n_tags.get("\"${release['tag_name']}\"").then |$r| {
      next($release + {'_tag_commit' => $n_tags[$release['tag_name']]})
    }
  }.filter |$r| { $r['_tag_commit'] }

  # FIXME: paginate if no tag is found (how to loop an increment page?)
  $commits_resultset = run_task_with(
    'http_request', $github_repo, "Get commits along branch '${branch}' for ${github_repo.name}"
  ) |$repo_target| {
    {
      'base_url'      => $github_repo.facts['commits_url'].releng::expand_uri( {} ),
      'method'        => 'get',
      'headers'       => {
        'Accept'        => 'application/vnd.github.v3+json',
        'Authorization' => "token ${github_api_token.unwrap}",
      },
      'body' => {
        'sha'      => $branch,
        'per_page' => 30,
        'page' => 1,
      },
      'json_endpoint' => true
    }
  }

  $tags = $tags_resultset[0].value['body']
  $commits = $commits_resultset[0].value['body']

  $tagged_commits = $commits.filter |$c| {  $c['sha'] in  $releases.map |$r| { $r['_tag_commit']['sha'] } }
  if $tagged_commits.empty { fail_plan( "No tags found in the first ${commits.count} commits; FIXME: implement paging for commit search" ) }
  $headmost_tagged_commit_sha = $tagged_commits[0]['sha']

  # FIXME: the latest tag may not be a GitHub release!
  $headmost_release = $releases.filter |$r| { $r['_tag_commit']['sha'] == $headmost_tagged_commit_sha }[0]

  return($headmost_release)
}
