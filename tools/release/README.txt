#  These are scripts I stole from Liz.

When going to release I cloned simp-core and switched to the branch that I was going to release. At the root of this branch I run:
  generate_component_release_status.rb 
Which outputs  component_release_status.txt

Then I ran:
   report_component_release_status.rb -i ./component_release_status.txt  --report-tag-current > component_report.txt

and it gives me a pretty little report on what has been released.  I need to go through the code to see exactly what it is doing but it was a good starting point.


