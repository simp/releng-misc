# Prints number of Targets from inventory
#
# @param targets
#    By default: `github_repos` group from inventory
#
# @param target_dir
#    Local directory to download assets into
#
plan releng::github_download_release_assets(
  TargetSpec $targets = 'github_repos',
  Stdlib::Absolutepath $target_dir = "${system::env('PWD')}/_release_assets",
  Hash $repo_release_list = {
  },
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_TOKEN')),
  String $exclude_substrings = [
    '.src.noarch'
  ]
){
  $github_repos = get_targets($targets)


  # FIXME currently just downloads latest release
  $releases_resultset = run_task_with(
    'http_request', $github_repos, "Get GitHub releases"
  ) |$repo_target| {
    {
      'base_url' => releng::expand_uri( $repo_target.facts['releases_url'], {} ),
      'method'   => 'get',
      'headers' => {
        'Accept'        => 'application/vnd.github.v3+json',
        'Authorization' => "token ${github_api_token.unwrap}",
      },
      'json_endpoint' => true
    }
  }

  $release_assets = Hash( $releases_resultset.ok_set.to_data.map |$result| {
    $rel_data = $result.get('value.body').filter |$rel| {
      !$rel['draft'] and !$rel['prerelease']
    }[0].with |$rel| { # take the first result (most recent) # FIXME this would normally filter on the target tag
      $rel.filter |$key,$v| {
        $key in ['assets', 'id','tag_name','assets', 'url', 'html_url']
      }
    }
    [$result['target'], $rel_data]
  })

  apply('localhost', '_description' => "Ensure target directory at '${target_dir}'"){
    file{ $target_dir: ensure => directory }
  }

  # For each release download each asset (filter on/out el7? el8? src?)
  $release_download_results = $release_assets.map |$repo_name, $release| {
    out::message("== $repo_name (Release: ${release['tag_name']}")
    out::verbose("  -- Release page: ${release['html_url']}")
    $assets = $release['assets']
    $asset_dl_results = $assets.map |$asset| {
      out::message("  -- Asset: ${asset['name']}")
      log::info("  -- Asset URL: ${asset['browser_download_url']}")

      # TODO reject downloads based on pattern?

      $dl_result = run_command(
        "curl -o '${target_dir}/${asset['name']}' -sS -L -H '${asset['content']}' '${asset['browser_download_url']}'",
        'localhost',
        "Download ${asset['browser_download_url']}"
      )
    }
  }


  debug::break()
  out::message( "Repos: ${github_repos.size}" )
}
