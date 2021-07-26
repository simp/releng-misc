# Component Release Tools

This directory contains miscellaneous tools used when preparing a SIMP release.
A few of them will be described in more detail below.

**CAUTION: NONE of these tools have tests are therefore are guaranteed to be buggy.**

## Preconditions

* You will need GitLab and GitHub tokens to run some of the programs in this
  directory.
* Be sure to `bundle update` at the top level of the project to ensure you
  have all the necessary gems.

## generate_simp_release_status.rb

This tool gathers information about the release/releasability status of SIMP
components. It queries GitHub and GitLab for the information for each SIMP
component in an input Puppetfile and then generates a CSV-formatted table with
the information. That table can be imported into a SIMP release Confluence page.

### Usage

The most common usage of this script is to assess the status of the SIMP
components specified by simp-core Puppetfiles on its master branch and its
latest tag. Simply run as follows:

```bash
 GITLAB_ACCESS_TOKEN=<your personal gitlab access token> \
 GITHUB_ACCESS_TOKEN=<your personal github access token> \
 bundle exec tools/release/generate_simp_release_status.rb \
  -o simp_component_release_status_2021_07_21.csv
```

This will report the GitHub release and GitLab test status of SIMP components in
simp-core's Puppetfile.branches, along with their versions found in simp-core's
interim Puppetfile.pinned and the final Puppetfile.pinned for the last SIMP
release. The report is written to the specified output in CSV format. In
addition a log file with (most of the) messages that were sent to the screen
will be created.

You can specify your own Puppetfile in lieu of using Puppetfile.branches from
simp-core, can choose how much information is retrieved, and can specify the
work directory used via other command line options. Use the `--help` option to
see the latest-available options.

### Important caveats

* The code is functional but ugly. It has the entrophy you would expect of
  ad-hoc, untested, unreviewed code. If you were to distill the reason why this
  code is here, it is because it automates some of the tedious work necessary to
  identify which modules can be/should be/have been be released.
* The code is very slow (>5 minutes to run) because the expensive GitHub/GitLab
  API operations have not been parallelized.
* The code *attempts* to assess whether enough GitLab jobs have been run in
  an appropriate successful pipeline to signify actual success. At this point,
  the logic is very crude and you should **not** rely on the reported, overall
  GitLab test status. Instead, for all components whose 'Gitlab Test Status'
  begins with "SUCCESS", you should examine the list of passed GitLab jobs to
  assess whether the coverage looks reasonable.
* It is possible that some of the error messages sent to the screen are not
  captured in the log file. This is because some of the libraries this code
  uses send message directly to $stderr.
* The code excludes the vox_selinux and rsync_data_pre64 Puppetfile entries as
  it can't correctly report results for them.
* The script originally reported whether component RPMs were published to
  packagecloud. This feature has been commented out in the code because it
  needs to be updated to query the official SIMP repositories.

### Information reported

As of 2021/7/21 the generated table contains the following fields:

* *Component*:
  The short name of the component as it appears when the dependencies are
  checked out from the Puppetfile

* *Proposed Version*:
  The latest available version extracted from the component's metadata.json
  or RPM spec file.

* *Current Pinned Version*:
  The version in simp-core's Puppetfile.pinned. When not set to a tag,
  the version will be reported as 'latest'.

* *Version in Last SIMP*:
  The version recorded in simp-core's Puppetfile.pinned for the last tagged
  release.

* *GitHub Released*:
  GitHub release status.

  * Will be the date the component was released, 'N',
    'tagged only' or 'unknown'.
  * 'tagged only' means the component was tagged but not released to GitHub.
  * 'unknown' means the information could not be determined.

* *Forge Released*:
  PuppetForge release status.

  * Will be the date the component was released, 'N', 'N/A', 'unknown'
  * 'N/A' means the component is not a Puppet module.
  * 'unknown' means the information could not be determined.


* *GitLab Current*:
  Whether the latest GitHub git ref matches the latest GitLab git ref.

  * Values are 'true' or 'false'.
  * A mismatch can mean that the sync has not yet been done, or, sync'ing
    has been stopped. You can manually attempt the sync to determine if there
    is a sync problem. When there is a sync problem, it needs to be reported
    in the simp-releng Slack chatroom.

* *GitLab Test Status*:
  Automated assessment of whether there is a successful GitLab pipeline for
  the appropriate git ref for released/releasable version of the component and
  the URL to that pipeline.

  * When the component has been released, the git ref used is that of the
    released version. Otherwise, the latest GitHub git ref is used.
  * Status begins with "SUCCESS" when a pipeline for the appropriate git ref has
    been found, the pipeline has succeeded and it appears to have "enough" unit
    and acceptance test jobs per its .gitlab-ci.yml.
    (DO NOT BLINDLY ACCEPT THIS ASSESSMENT. SEE CAVEATS ABOVE!!!)
  * Status begins with "INCOMPLETE SUCCESS" when a pipeline for the appropriate
    git ref has been found, the pipeline has succeeded, but it does not appear
    to have "enough" unit and acceptance test jobs per its .gitlab-ci.yml.
  * Status of 'none' means no pipeline for the appropriate git ref has been found.
  * Status of 'N/A' means there is no .gitlab-ci.yml for the released/releasable
    version of the component.

* *GitLab Passed Jobs*:
  List of passed jobs for the appropriate pipeline for the component, grouped by stage.

* *GitLab Failed Jobs*:
  List of failed jobs for the appropriate pipeline for the component, grouped by stage.

* *Changelog*:
  URL to the current project changelog.

## trigger_pipeline.rb

This tool triggers GitLab pipelines with ``SIMP_FORCE_RUN_MATRIX='yes'`` and
``SIMP_MATRIX_LEVEL=2`` for any number of specified SIMP repositories.

Until weekly scheduled GitLab pipelines that run unit and acceptance tests are
re-enabled in GitLab, this can be used to run the pipelines necessary to ensure
SIMP components have been adequately tested prior to release.

### Usage

```bash
GITLAB_ACCESS_TOKEN=<your personal gitlab access token> \
 bundle exec tools/release/trigger_pipeline.rb \
   pupmod-simp-nfs pupmod-simp-rsyslog simp-adapter
```
