# Jira Tools


## jira_pulls.rb


$ ruby jira_pulls.rb -h

     Usage: jira_pull [options] (default will pull only the current sprint)

      -h, --help                       Help
      -s, --sprint NUMBER              Sprint
      -d, --closed since days          number of days (changes to closed query)
      -o, --output DIR                 Output Dir (full path)

-s will pull a sprint given the sprint number assigned by Jira (you may need to look it up, usually by hovering over a report option)

-d will list the tickets closed within the number of days given

-o will copy the output file to the specified directory (please use a full path)

NOTES: 
* the default option is current sprint 
* the -s and -d options cannot be used together



## create_tix_from_confluence.rb -h

$ ruby create_tix_from_confluence.rb -h

    Usage: create_tickets [options]

      -h, --help                       Help
      -f, --input NAME                 Input file or directory name
      -s, --sprint NUMBER              Input sprint number (Jira)

-f input file (should be a comma-separated file containing the fields:

  * ticket id (generated for the table to associate parents and children)
    note that a sub-ticket has parent.number
  * summary (short ticket summary)
  * description (longer ticket description)
  * component (component name)
  * blocker (if a previous ticket blocks it, put its ticket id here)
  * points (story points)
  


-s sprint number assigned by Jira (you may need to look it up, usually by hovering over a report option)

