# Read a Puppetfile of tagged mods and download the RPMs attached to their 
# GitHub release pages
#
# @param targets
#    By default: `github_repos` group from inventory
#
#    If a target has the var 'release_tag', that tag will be used to identify
#    the release to download.  Otherwise, the latest release will be downloaded.
#
# @param target_dir
#    Local directory to download assets into
#
plan releng::download_assets_from_puppetfile(
  TargetSpec $targets = 'github_repos',
  Variant[Stdlib::HTTPUrl,Stdlib::Absolutepath] $puppetfile = 'https://raw.githubusercontent.com/simp/simp-core/master/Puppetfile.pinned',
  Stdlib::Absolutepath $target_dir = "${system::env('PWD')}/_release_assets",
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_TOKEN')),
  Array[String[1]] $exclude_patterns = [
    '\.src.*\.rpm$',
    '\.el7.*\.rpm$',
  ]
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
  $pf_mods = releng::parse_puppetfile($puppetfile_data)

  $github_repos = get_targets($targets)

  $pf_gh_repos = $pf_mods.map |$pf_path, $pf_mod| {
     $git_url = $pf_mod['git'].regsubst(/\.git$/,'')

     $matching_gh_repos = $github_repos.filter |$gh_repo| {
       $git_url  ==  $gh_repo.facts['clone_url'].regsubst(/\.git$/,'')
     }.releng::empty2undef.lest || {
       log::error( "ERROR: no GitHub repos' clone_url match Puppetfile mod '${pf_mod['name']} (${pf_mod['git']})" )
       log::warn( "Trying workaround...")

       # FIXME
       $git_url_wa = $git_url.regsubst(/\/simp-rsync$/,'/simp-rsync-skeleton')
       $github_repos.filter |$gh_repo| {
         $gh_clone_url = $gh_repo.facts['clone_url'].regsubst(/\.git$/,'')
         $is_match = ($git_url_wa == $gh_clone_url)
         log::debug( "  --> git_url_wal : '${git_url_wa}'")
         log::debug( "  --> gh_clone_url: '${gh_clone_url}' (${is_match})" )
         $is_match
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
    #
    # Currently 1 failing ((clone_url redirects to https://github.com/simp/simp-rsync-skeleton):
    #  => {
    #           "git" => "https://github.com/simp/simp-rsync",
    #  "install_path" => "src/assets",
    #      "mod_name" => "rsync_data_pre64",
    #  "mod_rel_path" => "src/assets/rsync_data_pre64",
    #          "name" => "simp-rsync_data_pre64",
    #      "rel_path" => "src/assets/simp-rsync_data_pre64",
    #     "repo_name" => "simp-rsync",
    #           "tag" => "6.2.1-2"
    #  }
    #
    #  However:
    #    These two puppetfle mods clone from the same location (after redirects)
    #    [  2] "src/assets/rsync_data:       https://github.com/simp/simp-rsync-skeleton",
    #    [  3] "src/assets/rsync_data_pre64: https://github.com/simp/simp-rsync",

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

  return($results)
}
