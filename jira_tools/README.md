# Jira Tools


<!-- vim-markdown-toc GFM -->

* [Setup](#setup)
  * [Obtaining Jira credentials](#obtaining-jira-credentials)
* [Usage](#usage)
  * [jira_pulls.rb](#jira_pullsrb)
  * [create_tix_from_confluence.rb](#create_tix_from_confluencerb)

<!-- vim-markdown-toc -->

## Setup

1. Run `bundle` to install Gem dependencies
2. Ensure the environment variable `JIRA_API_TOKEN` is set in `<login>:<token>` format (for create_tix_from_confluence.rb only):

   ```sh
   export JIRA_API_TOKEN=me@here.com:123456789012
   ```
### Obtaining Jira credentials

To get your API token:

* In Jira, click your profile (top-right
  * Account settings
  * Security
  * Api token

## Usage

### jira_pulls.rb

```console
$ bundle exec ruby jira_pulls.rb -h

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
```

### create_tix_from_confluence.rb

This script creates a batch of Jira tickets

* Input: a CSV file, based on one of the tables from https://simp-project.atlassian.net/wiki/spaces/SD/pages/1920008207/Test+Plan+SIMP+6.6.0 
(Note: The most effective way to create this table is to select the table, copy it to google sheets [this seems to maintain the cells' integrity] and then file/download/CSV)


```console
$ bundle exec ruby create_tix_from_confluence.rb -h

    Usage: create_tickets [options]

      -h, --help                       Help
      -f, --input NAME                 CSV Input file or directory name
      -p, --project PROJECT            Jira Project to create tickets (default: JJTEST)

-f input file (should be a comma-separated file containing the fields:

  * ticket id (generated for the table to associate parents and children)
    note that a sub-ticket has parent.number
  * summary (short ticket summary)
  * description (longer ticket description)
  * component (component name)
  * blocker (if a previous ticket blocks it, put its ticket id here)
  * points (story points)


-p Jira project (`JJTEST` by default, use `SIMP` when ready to go live)
```
* Output: To ensure the run was successful, check the allresults.json

