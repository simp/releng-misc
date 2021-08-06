# Return `github_inventory` Targets that represent each `mod` in a Puppetfile
#
# Targets are sourced by matching a mod's `:git` to a `clone_url` from `$targets`
#
# Each github_inventory+mod Target includes Puppetfile-specific fact(s):
#
#   * `_pf_mod` Puppetfile data for the `mod` entry
#   * `_release_tag` (for mods with a `:tag`)
#   * `_tracking_branch` (for mods with a `:branch`)
#
# @param targets
#    `github_inventory` Targets with clone_urls expected to match the
#    Puppetfile mod' :git urls
#
# @param puppetfile
#    Path or URL to simp-core Puppetfile.<method> that identifies mods'
#    (github repo) clone_url and release tags
#
# @param pf_mod
#    data from a Puppetefile 'mod' entry
#
plan releng::puppetfile::github::repo_targets(
  TargetSpec $targets = 'github_repos',
  Variant[Stdlib::HTTPUrl,Stdlib::Absolutepath] $puppetfile = 'https://raw.githubusercontent.com/simp/simp-core/master/Puppetfile.pinned',
  Hash $pf_mods = run_plan( 'releng::puppetfile::data', { 'puppetfile' => $puppetfile }),
){
  $github_repos = get_targets($targets)

  # Match each Puppetfile 'mod' to a GitHub repo Target with a matching url
  $pf_gh_repos = $pf_mods.map |$pf_path, $pf_mod| {
     $git_url = $pf_mod['git'].regsubst(/\.git$/,'')

     $matching_gh_repos = $github_repos.filter |$gh_repo| {
       $git_url  ==  $gh_repo.facts['clone_url'].regsubst(/\.git$/,'')
     }.releng::empty2undef.lest || {
       log::error( "ERROR: no GitHub repo's clone_url matched Puppetfile mod '${pf_mod['name']} (${pf_mod['git']})" )
       $workaround = run_plan( 'releng::puppetfile::github::workaround__unmatched_git_url', {
         'pf_mod' => $pf_mod,
         'git_url' => $git_url,
       })
       $workaround
     }

     # Add Puppetfile-related facts
     $matching_gh_repos.each |$gh_repo| {
       $gh_repo.add_facts( { '_pf_mod' => $pf_mod } )
       if $pf_mod['tag'] { $gh_repo.add_facts({ '_release_tag' => $pf_mod['tag'] }) }
       if $pf_mod['branch'] { $gh_repo.add_facts({ '_tracking_branch' => $pf_mod['branch'] }) }
     }

     if $matching_gh_repos.size > 1 {
       log::error("ERROR: More than 1 github repo targets found for Puppetfile mod at '${pf_path}':\n\n${matching_gh_repos.to_yaml}")
       debug::break()
     }
     [$pf_path, $matching_gh_repos[0]]
  }.with |$x| { Hash($x) }


  $unmatched_pf_mods = $pf_gh_repos.filter |$k,$v| { $v =~ Undef }
  if $unmatched_pf_mods.size > 0 {
    $bulleted_repo_list = $unmatched_pf_mods.map |$k, $v| { "  - ${k}" }.join("\n")
    $msg_head = "ERROR: Could not find GitHub repo target for ${unmatched_pf_mods.size} Puppetfile mods"
    $msg = "${msg_head}:\n\n${bulleted_repo_list}"
    log::error($msg)
    log::error("$msg_head (see list above)")
    debug::break()  # TODO - Should the plan fail here?  should there be an option?
  }

  return( $pf_gh_repos.filter |$k,$v| { $v =~ NotUndef } )
}
