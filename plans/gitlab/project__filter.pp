# Returns gitlab_inventory Targets, filtered by project path (name without
# group) according to an include/ignore list.
#
# @note For users wishing to limit the repositories they might effect, it's more
#   efficient (and API-friendly) to filter projects from the `inventory.yaml`,
#   using the gitlab_inventory plugin's `block_list` and `allow_list`.
#
# @param targets
#    By default: `gitlab_projects` group from inventory
#
# @param exclude_list
#    List of project names to exclude
#
#        Note that it's more efficient (and API-friendly) to do this from the
#        `inventory.yaml`, using the gitlab_inventory plugin's `block_list`
#
# @param include_list
#    List of project names to include
#
#        Note that it's more efficient (and API-friendly) to do this from the
#        `inventory.yaml`, using the gitlab_inventory plugin's `allow_list`
#
# @private true
# @api private
plan releng::gitlab::project__filter(
  TargetSpec $targets = 'gitlab_projects',
  Optional[[Array[Variant[String,Regexp]]]] $exclude_list = [ /gitlab-oss/ ],
  Optional[[Array[Variant[String,Regexp]]]] $include_list = []
){
  # Get targets and filter out anything in the exclude/include list
  $gitlab_projects = get_targets($targets).filter |$target| {
    # Remove targets with names that match something in the $exclude_list
    $ignore = $exclude_list.all |$i| {
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
