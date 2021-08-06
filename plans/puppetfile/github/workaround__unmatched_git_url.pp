# Download all RPMs from GitHub release pages of each `mod` in a Puppetfile.
#
# @api private
#
# @param pf_mod
#    data from a Puppetefile 'mod' entry
#
# @param targets
#    `github_inventory` Targets with clone_urls that match mods in
#    the Puppetfile
#
plan releng::puppetfile::github::workaround__unmatched_git_url(
  TargetSpec $targets = 'github_repos',
  Hash $pf_mod,
  Stdlib::HTTPUrl $git_url,
){
  $github_repos = get_targets($targets)

  log::warn( "Trying workaround...")

  $git_url_workaround = $git_url.regsubst(/\/simp-rsync$/,'/simp-rsync-skeleton')

  # FIXME this hack only fixes a redirect for a known repo; won't help others
  # FIXME ...is there a way to generalize this approach and is it worth it?
  $workaround_repo = $github_repos.filter |$gh_repo| {
    $gh_clone_url = $gh_repo.facts['clone_url'].regsubst(/\.git$/,'')
    $git_url_workaround == $gh_clone_url
  }.map |$gh_repo| {
    log::warn( "  ...workaround succeeded!")
    $t = Target.new( "${pf_mod['name']}.workaround" )
    $gh_repo.config.each |$k, $v| { $t.set_config( $k, $v ) }
    $gh_repo.vars.each |$k, $v| { $t.set_var($k, $v) }
    $t.add_facts( $gh_repo.facts )
    $t
  }

  return( $workaround_repo )
}
