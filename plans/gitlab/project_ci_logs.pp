# Find (and optionally erase) all GLCI jobs+logs within a daterange
#
# Targets are defined by inventory.yaml
#
# @param targets
#    A `gitlab_inventory` Target for each GitLab Project to check
#
# @param project_dir
#   The Bolt project directory
#
# @param gitlab_api_token
#   The Gitlab API token that will status/configure GitLab projects
#       (needs `read-write-api` scope)
#
# @param action
#   Either `show` or `erase` the jobs/logs between the specified dates
#
# @param max_job_pagination
#   How many pages of each project's jobs to query
#        Dial this back when hitting API rate-limits (risks missing jobs)
#
# @param exclude_list
#    List of project names to exclude
#
#    Note that it's more efficient (and API-friendly) to do this from the
#    inventory.yaml, using the gitlab_inventory plugin's `block_list`
#
# @param include_list
#    List of project names to include, as Strings or Patterns.
#
#    Note that it's more efficient (and API-friendly) to do this from the
#    inventory.yaml, using the gitlab_inventory plugin's `allow_list`
#
plan releng::gitlab::project_ci_logs (
  TargetSpec $targets = 'gitlab_projects',
  Stdlib::Absolutepath $project_dir = system::env('PWD'),
  Sensitive[String[1]] $gitlab_api_token = Sensitive.new(system::env('GITLAB_API_PRIVATE_TOKEN')),
  Enum[show,erase] $action = 'show',
  Integer $max_job_pagination = 20,
  String $start_at = '2021-02-11T13:00:00.000Z',
  String $end_at   = '2021-02-16T01:16:00.000Z',
  Enum[created_at,started_at,any] $start_type = 'started_at',
  Optional[[Array[Variant[String,Regexp]]]] $exclude_list = [ /gitlab-oss/ ],
  Optional[[Array[Variant[String,Regexp]]]] $include_list = undef
){
  $gitlab_projects = run_plan(
    'releng::gitlab::project__filter',
    {
      'targets'      => $targets,
      'exclude_list'  => $exclude_list,
      'include_list' => $include_list,
    }
  )

  $matching_projects_jobs = run_plan(
    'releng::gitlab::project__ci_job_daterange_filter',
    {
      'targets'            => $gitlab_projects,
      'gitlab_api_token'   => $gitlab_api_token,
      'start_at'           => $start_at,
      'end_at'             => $end_at,
      'max_job_pagination' => $max_job_pagination,
    }
  )

  ### # Example: Only target jobs that ran on gitlab.com runners
  ### #
  ### # This code was specific to a particular use case, and should remain commented.
  ### # It has been preserved to demonstrate how/where to add case-specific filters
  ### # to target specific attributes of CI jobs + logs to show/erase.
  ### #
  ### # The first line would replace the final `)` in the `run_plan` function above
  ### #------------------------------------------------------------------------------
  ### ).with |$matching_projects_jobs| {
  ###   Hash.new($matching_projects_jobs.map |$target_name,$jobs| {[
  ###     $target_name,
  ###     $jobs.filter |$j| { $j['runner']['description'] =~ /gitlab\.com$/ },
  ###   ]}).filter |$k,$matching_jobs| { $matching_jobs.size > 0 }
  ### }
  ### #------------------------------------------------------------------------------

  $matching_projects = $gitlab_projects.filter |$t| { $matching_projects_jobs.any |$k,$v| { $k == $t.name } }
  $total_matching_jobs = $matching_projects_jobs.map |$target_name,$jobs| { $jobs.size }.reduce(0) |$m,$v| { $m + $v }

  # Print all matching jobs, grouped by GitLab Project
  # --------------------------------------------------
  $match_report = $matching_projects_jobs.map |$target_name,$jobs| {
    [
      "\n== ${target_name} ${jobs.size}",
      $jobs.map |$j| { "  ${j['started_at']}  ${j['web_url']}" },
    ].join("\n")
  }.join("\n").with |$x| { "${x}\n\n---\nTotal matching jobs: ${total_matching_jobs}" }
  out::message( $match_report )

  $match_log_file = [$project_dir , Timestamp.new.strftime( 'matching-gitlab-ci-jobs-%Y%m%d-%H:%M:%S.log' )].join('/')
  file::write( $match_log_file, $match_report )


  # ------------
  # action: show
  # ------------
  if $action == 'show' { return() } # No further action needed


  # -------------
  # action: erase
  # -------------

  # By this point, we've looked up many pages worth of CI job/log for each
  # project.  In an active Gitlab group with many projects and pipelines,
  # this could have easily triggered hundreds of API calls in the last few
  # seconds.  So, we need to consider our GitLab token's per-minute API
  # rate-limit.
  #
  # If we immediately hit the API again to erase all those jobs/logs,
  # it would be likely to trigger GitLab's API abuse detection.  So, we take a
  # few precautions:
  #
  #   * The plan pauses at this point for 60 seconds, to refresh the rate limit.
  #   * The API calls to erase each job are not run in parallel.
  #
  # Linux users: when erasing large quantities of CI jobs/logs, your `nofile`
  # settings in /etc/security/limits.conf will probably have to be quite high
  # or Bolt will hit your limit and fail (check with `ulimit -n`).
  if $action == 'erase' {
    out::message( "=== Erasing matched CI jobs" )
    [].with |$x| { $i=5; Integer[0,60].step($i).reverse_each.map |$n| {
      if $n > 0 {
        out::message( "   Waiting $n more seconds before preceding (to cool down API rate-limiting counters)..." )
        ctrl::sleep($i)
      } else {
        out::message( "   Time's up!  Resuming plan..." )
      }
    }}

    $_plan_result = $matching_projects.map |$t| {
      $jobs = $matching_projects_jobs[ $t.name ]
      out::message( "=== Erasing ${jobs.size} ci jobs & logs from ${t.name}" )
      $results = $jobs.map |$job| {
        run_task(
          'http_request', $t,
          "Erase job ${job['id']} (${job['name']}, ${job['started_at'].lest || { $job['created_at'] }}) from ${t.name}",
          {
            ### '_catch_errors' => true,
            'base_url'      => "${t.facts['_links']['self']}/",
            'path'          => "jobs/${job['id']}/erase",
            'method'        => 'post',
            'headers'       => { 'Authorization' => "Bearer ${gitlab_api_token.unwrap}" },
            'json_endpoint' => true,
          }
        )
      }
      [$t.name, $results]
    }
    out::message( "=== Finished erasing ci jobs & logs" )
    Hash.new($_plan_result)
  }
}
