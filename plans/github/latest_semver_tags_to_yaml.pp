# Report the highest SemVer tag for each repo (that has SemVer tags), including
# release data (if a release exists for that tag) and uploaded assets
#
# @summary Write the latest_semver_tags to a local YAML file
#
# @note reports repos with "SemVer-ish" tags (includes `/^v/` and `/-d$/`)
#
# @param targets
#    `github_inventory` Targets (or inventory group)
#
# @param github_api_token
#    GitHub API token.  Doesn't require any scope for public repos.
#
# @param display_result
#    When `true`, plan prints result using `out::message`
#
# @param output_file
#    Path of report file for be generated
#
# @param return_result
#    When `true`, plan returns data in a ResultSet
#
plan releng::github::latest_semver_tags_to_yaml (
  TargetSpec           $targets = 'github_repos',
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_TOKEN')),
  Stdlib::Absolutepath $output_file = [ 
    system::env('PWD'), 
    Timestamp.new.strftime( 'github_repos_latest_semver_tags-%Y%m%d-%H:%M:%S.yaml' )
  ].join('/'),
  Boolean $display_result = true,
  Boolean $return_result  = false,
) {
  $results = run_plan(
    'github_inventory::latest_semver_tags',
    {
      'targets'        => $targets,
      'display_result' => $display_result,
      'return_result'  => true,
    }
  )
  file::write( $output_file, $results.to_yaml )
  out::message("Wrote results to '${output_file}'")
  if $return_result { return $results }
}
