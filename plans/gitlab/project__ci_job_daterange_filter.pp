# Returns a hash of 'project name' => [ job hashes  ] for all project' CI jobs
# within a certain date range
#
# @note This plan is intended to be run by other plans as a sub plan.
#
# @param targets
#    By default: `gitlab_projects` group from inventory
#
# @param gitlab_api_token
#   The Gitlab API token that will status/configure GitLab projects
#       (needs `read-write-api` scope)
#
# @param max_job_pagination
#   How many pages of each project's jobs to query
#        Dial this back when hitting API rate-limits, risks missing jobs
#
# @private true
# @api private
plan releng::gitlab::project__ci_job_daterange_filter(
  TargetSpec $targets = 'gitlab_projects',
  Sensitive[String[1]] $gitlab_api_token = Sensitive.new(system::env('GITLAB_API_PRIVATE_TOKEN')),
  String $start_at = '2021-02-11T13:00:00.000Z',
  String $end_at   = '2021-02-16T01:16:00.000Z',
  Integer $max_job_pagination = 20,
  Enum[created_at,started_at,any] $start_type = 'started_at',
){
  $delete_range_start = Timestamp.new( $start_at )
  $delete_range_end = Timestamp( $end_at )
  $gitlab_projects = get_targets($targets)

  $job_results = run_task_with(
    'releng::gitlab::api_request',
    $gitlab_projects,
    "Gathering CI jobs data for GitLab projects",
    { '_catch_errors' => true }
  ) |$t| {{
    'path'             => "${t.facts['_links']['self']}/jobs",
    'gitlab_api_token' => $gitlab_api_token.unwrap,
    'max_pages'        => $max_job_pagination,
  }}

  $matching_projects_jobs = Hash.new( $job_results.ok_set.results.map |$r| {
    [ $r.target.name,
      $r.value['body'].filter |$j| {
        case $start_type {
          'started_at': {
            if $j['started_at'] =~ Undef { next() }
            $started_at = Timestamp.new($j['started_at'])
          }
          'created_at':  { $started_at = Timestamp.new($j['created_at']) }
          'any', default: {
            $started_at = $j['started_at'] ? {
              Undef   => Timestamp.new($j['created_at']),
              default => Timestamp.new($j['started_at']),
            }
          }
        }
        if ( $started_at >= $delete_range_start and $started_at < $delete_range_end  ) { next($j) }
        warning( "skipping '${r.target.name} job ${j['id']}: outside of date range (started_at: '${started_at}')")
      }
    ]
  } ).filter |$k,$matching_jobs| { $matching_jobs.size > 0 }

  return( $matching_projects_jobs )
}
