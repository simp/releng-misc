# Prints number of Targets from inventory
#
# @param targets
#    By default: `gitlab_projects` group from inventory
#
plan releng::gitlab_project_count(
  TargetSpec $targets = 'gitlab_projects'
){
  $gitlab_projects = get_targets($targets)
  out::message( "Repos: ${gitlab_projects.size}" )
}
