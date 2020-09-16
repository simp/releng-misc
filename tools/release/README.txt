#  These are scripts I stole from Liz.

When going to release I cloned simp-core and switched to the branch that I was going to release. At the root of this branch I run:
  generate_component_release_status.rb 
Which outputs  component_release_status.txt

Then I ran:
   report_component_release_status.rb -i ./component_release_status.txt  --report-tag-current > component_report.txt

and it gives me a pretty little report on what has been released.  I need to go through the code to see exactly what it is doing but it was a good starting point.

##################

You will need GitLab and GitHub tokens to run this program or the queries will
fail due to rate limiting. Also, note that the RPM publication checks are not
current, as they check packagecloud.

At top level:

bundle update

GITLAB_ACCESS_TOKEN=<> \
 GITHUB_ACCESS_TOKEN=<> \
 bundle exec tools/release/generate_simp_release_status_full.rb \
  -p Puppetfile.branches \
  --last-release-puppetfile Puppetfile.6.4.0-0 \
  -o simp_component_release_status_2020_09_16.csv

