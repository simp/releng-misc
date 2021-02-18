# Returns gitlab_inventory Targets, filtered by project path (name without
# group) according to an include/ignore list.
#
# This plan is intended to be run by other plans as a sub plan.
#
# For users wishing to limit the repositories they might effect, it's more
# efficient (and API-friendly) to do filter projects in the inventory.yaml,
# using the gitlab_inventory plugin's `block_list` and `allow_list`.
#
# @param targets
#    By default: `gitlab_projects` group from inventory
#
# @param ignore_list
#    List of project names to ignore, as Strings or Patterns
#
#    Note that it's more efficient (and API-friendly) to do this from the
#    inventory.yaml, using the gitlab_inventory plugin's `block_list` argument.
#
# @param include_list
#    List of project names to include, as Strings or Patterns
#
#    Note that it's more efficient (and API-friendly) to do this from the
#    inventory.yaml, using the gitlab_inventory plugin's `allow_list` argument.
#
# @private true
plan releng::gitlab_project__filter(
  TargetSpec $targets = 'gitlab_projects',
  Optional[[Array[Variant[String,Regexp]]]] $ignore_list = [
    /gitlab-oss/,
  ],
  Optional[[Array[Variant[String,Regexp]]]] $include_list = []
){
  # Get targets and filter out anything in the ignore/include list
  $gitlab_projects = get_targets($targets).filter |$target| {
    # Remove targets with names that match something in the $ignore_list
    $ignore = $ignore_list.all |$i| {
      case $i {
        Regexp: { $target.facts['path'] !~ $i }
        default: { $target.facts['path'] != $i }
      }
    }
    $include = $include_list.any |$i| {
      case $i {
        Regexp: { $target.facts['path'] =~ $i }
        default: { $target.facts['path'] == $i }
      }
    }
    if $include_list.empty { $ignore } else { $ignore and $include }
  }

  return( $gitlab_projects )
}
