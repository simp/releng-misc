# Read a Puppetfile of tagged mods and download the RPMs attached to their
# GitHub release pages
#
# @param targets
#    By default: `github_repos` group from inventory
#
# @param puppetfile
#    Path or URL to simp-core Puppetfile (e.g., `Puppetfile.pinned`) to identify
#    git repos and release tags
#
# @param target_dir
#    Local directory to download assets into
#
plan releng::download_assets_from_puppetfile(
  TargetSpec $targets = 'github_repos',
  Variant[Stdlib::HTTPUrl,Stdlib::Absolutepath] $puppetfile = 'https://raw.githubusercontent.com/simp/simp-core/master/Puppetfile.pinned',
  Stdlib::Absolutepath $target_dir = "${system::env('PWD')}/_release_assets",
  Array[String[1]] $exclude_patterns = [
    '\.src.*\.rpm$',
    '\.el7.*\.rpm$',
  ],
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_TOKEN')),
){
  if $puppetfile =~ Stdlib::HTTPUrl {
    $dl_result = run_command(
      "curl -sS -L -H 'text/plain' '${puppetfile}'",
      'localhost',
      "Get data from ${puppetfile}"
    )
    $puppetfile_data = $dl_result.ok_set.first.value['stdout']
  } else {
    $puppetfile_data = file::read($puppetfile)
  }

  $pf_mods = releng::parse_puppetfile($puppetfile_data).with |$data| { Hash($data) }
  $github_repos = get_targets($targets)

  $pf_gh_repos = $pf_mods.map |$pf_path, $pf_mod| {
     $git_url = $pf_mod['git'].regsubst(/\.git$/,'')

     $matching_gh_repos = $github_repos.filter |$gh_repo| {
       $git_url  ==  $gh_repo.facts['clone_url'].regsubst(/\.git$/,'')
     }.releng::empty2undef.lest || {
       log::error( "ERROR: no GitHub repos' clone_url match Puppetfile mod '${pf_mod['name']} (${pf_mod['git']})" )

       # FIXME this hack fixes a redirect for a single known repo; won't help others
       log::warn( "Trying workaround...")
       $git_url_wa = $git_url.regsubst(/\/simp-rsync$/,'/simp-rsync-skeleton')
       $github_repos.filter |$gh_repo| {
         $gh_clone_url = $gh_repo.facts['clone_url'].regsubst(/\.git$/,'')
         $git_url_wa == $gh_clone_url
       }.map |$gh_repo| {
         log::warn( "  ...workaround succeeded!")
         $t = Target.new( "${pf_mod['name']}.workaround" )
         $gh_repo.config.each |$k, $v| { $t.set_config( $k, $v ) }
         $gh_repo.vars.each |$k, $v| { $t.set_var($k, $v) }
         $t.add_facts( $gh_repo.facts )
         $t
       }
     }

     $matching_gh_repos.each |$gh_repo| {
       $gh_repo.add_facts( { '_pf_mod' => $pf_mod } )
       if $pf_mod['tag'] { $gh_repo.add_facts({ '_release_tag' => $pf_mod['tag'] }) }
       if $pf_mod['branch'] { $gh_repo.add_facts({ '_tracking_branch' => $pf_mod['branch'] }) }
     }

     if $matching_gh_repos.size > 1 {
       log::error("ERROR: Somehow there were more than 1 github repo targets found for puppetfile mod at '${pf_path}':\n\n${matching_gh_repos.to_yaml}")
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
    # FIXME : Should the plan fail here?  should there be an option?
    debug::break()
  }

  $matched_pf_mods = $pf_gh_repos.filter |$k,$v| { $v =~ NotUndef }
  $pf_gh_repo_targets = $matched_pf_mods.values

  $results = run_plan(
    'releng::github_download_release_assets',
    {
      'targets'          => $pf_gh_repo_targets,
      'target_dir'       => $target_dir,
      'exclude_patterns' => $exclude_patterns,
    }
  )

  #out::message( $pf_mods.map |$k,$v| { $v['tag'].lest || { "${v['branch']} (branch)" } }.join("\n") )
  $pf_mods.each |$k,$v| {
    out::message( "${v['repo_name']},${v['tag'].lest || { "${v['branch']} (branch)" } }" )
  }
  out::message( "TODO: prepare CSV report of pf_mods and their release status" )
  $pf_mods.each |$k,$v| {
    $t = $matched_pf_mods[$k]
    # $t.facts['_fallback_release_tag']
    # $t.facts['_release_tag']
    # $t.facts['_tracking_branch']
    # $t.facts['_release_assets'].size
    $gh_release_tag = $t.facts['_release_tag'].lest || {
      $t.facts['_fallback_release_tag'].then |$x| { "${x} (fallback)" }
    }
    $num_assets = $t.facts['_release_assets'].then |$x| { $x.size }.lest || { '---' }
    $name = $v['repo_name']
    $pf_tag = $v['tag'].lest || { "${v['branch']} (branch)" }
    out::message( "${name},${pf_tag},${gh_release_tag},${num_assets}" )
  }
  debug::break()
  return($results)
}
