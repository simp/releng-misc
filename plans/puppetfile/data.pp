# Return a Puppetfile's `mod` entries as a Hash with structure `path => data`
#
# @param puppetfile
#    URL or file path to a simp-core Puppetfile (e.g., `Puppetfile.pinned`)
#
# @param targets
#    Target from which to download/read Puppetfile
#
plan releng::puppetfile::data(
  TargetSpec $targets = 'localhost',
  Variant[Stdlib::HTTPUrl,Stdlib::Absolutepath] $puppetfile = 'https://raw.githubusercontent.com/simp/simp-core/master/Puppetfile.pinned',
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
  return( $pf_mods )
}
