# @summary
#   adds `_release_data` fact to Targets detailing the GitHub Release (including
#   assets) based on thier `_release_tag` fact.
#
# * If a Target doesn't have a `_release_tag` but does have a `_tracking_branch`
#   fact, then the `release_data` will be read from the latest release from
#   that repo (the version used will be in the `_fallback_release_tag` fact)
# * If a Target deosn't have a `_release_tag` or `_tracking_branch` fact, an
#   error message will be logged and the Target will go unchanged
#
# APPROACH 1 (GOOD): SELECT THE SPECIFIED TAG
#
# If the Target has the '_release_tag' fact, then use that tag's release data
# (`_release_tag` is added by the releng::puppetfile::github::repo_targets plan),
#
#
# APPROACH 2 (NOT AS GOOD): NO TAG GIVEN; FIGURE OUT THE BEST RELEASE
# TO USE
#
# FIXME : when no release_tag is given, should we:
#    - [ ] fail
#    - [ ] take the latest release tag along the tracking branch (we may not know it)
#    - [ ] take the latest release tag along the default branch
#    - [X] take the latest release tag, period
#    - [ ] do something fancy (tag version/range validation, etc)
#
# ^^ When answered: should/which of these behaviors should be determined by plan parameters?
plan releng::github::releases_data (
  TargetSpec $targets = 'github_repos',
  Sensitive[String[1]] $github_api_token = Sensitive.new(system::env('GITHUB_API_TOKEN')),
  Boolean $branches_fall_back_to_latest_release = true,
) {
  $github_repos = get_targets($targets)

  $releases_resultset = run_task_with(
    'http_request', $github_repos, "Get GitHub releases data for all repo targets"
  ) |$repo_target| {
    {
      'base_url' => $repo_target.facts['releases_url'].releng::expand_uri( {} ),
      'method'   => 'get',
      'headers' => {
        'Accept'        => 'application/vnd.github.v3+json',
        'Authorization' => "token ${github_api_token.unwrap}",
      },
      'json_endpoint' => true
    }
  }

  $releases_resultset.ok_set.each |$result| {
    $t = $result.target
    $rel_data = $result.value['body'].filter |$rel| { !$rel['draft'] }.with |$rels| {
      $t.facts['_release_tag'].then |$rel_tag| {
        $rels.filter |$rel| { $rel['tag_name'] == $rel_tag }.then |$x| { $x[0] }.lest || {
          $msg = "ERROR: Expected ${t.name} release with tag '${rel_tag}' but couldn't find it!"
          log::error($msg)
          false
        }
      }.lest || {
        $t.facts.get('_tracking_branch').then |$branch| {
          # If the Target knows it's _tracking_branch (from the puppetfile),
          # fall back to the latest release
          #
          # FIXME It *should* be "the highest release with a tag on the
          #        _tracking_branch," but for now that is way too fiddly to
          #        implement.
          #
          if $branches_fall_back_to_latest_release {
            log::error("${t.name} specifies no release tag")
            # TODO this should probably find the latest release along the tracking branch
            $fallback_tag = $rels[0].get('tag_name')
            $t.add_facts({'_fallback_release_tag' => $fallback_tag})
            log::warn("${t.name} uses tracking branch '${branch}'; falling back to latest tag '${fallback_tag}'")
            $rels[0]  # take the first result (most recent release) # FIXME not necessarily what we want; see above
          }
        }.lest || {
          $msg = "ERROR: ${t.name} has NO release tag or tracking branch!"
          log::error($msg)
          ## debug::break()
          ## fail_plan($error)
        }
      }
    }.with |$rel| {
      if $rel {
        $rel.filter |$key,$v| { $key in ['assets', 'id','tag_name','assets', 'url', 'html_url'] }
      }
    }

    # Add release-related facts to Targets (this _should_ be enough)
    if $rel_data {
      $t.add_facts( {'_release_data' => $rel_data} )
    }
  }

  return $github_repos
}
