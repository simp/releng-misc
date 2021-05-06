require 'rest-client'
require 'json'
require 'fileutils'
require 'optparse'

days = 0
sprintno = ''
outputdir = ''
pullfile='test.csv'
optsparse = OptionParser.new do |opts|
  opts.banner = "Usage: jira_pull [options] (default will pull only the current sprint)"
  opts.on('-h', '--help', 'Help') do
    puts opts
    exit
  end
  opts.on('-s', '--sprint NUMBER', 'Sprint') do
    |s| puts "sprint is #{s}"
    sprintno = s.strip
  end
  opts.on('-d', '--closed since days', 'number of days (channges to closed query)') do
    |d| puts "sprint is #{d}"
    days = d.strip
    pullfile = "tix_closed_#{days}.csv"
  end
  opts.on('-o', '--output DIR', 'Output Dir (full path)') do
    |o| puts "outdir is #{o}"
    outputdir = o.strip
  end
end
optsparse.parse!

# here is our jira instance
project_key = 'ABC'
jira_url = 'https://simp-project.atlassian.net/rest/api/2/search?'

# create query
if sprintno != ''
  filter = "jql=sprint=#{sprintno}"
elsif days != 0
  filter = "jql=resolved%3e%2d#{days}d%20and%20status=closed"
else
  filter = 'jql=sprint%20in%20openSprints()'
end

puts "query is #{filter}"

# set a max # results - defaults to 50 (we can switch this to a loop later)
total_issues = 1
ticket_count = 0
maxresults = 50

# while we have tickets still
while ticket_count < total_issues

  # call the code
  newfilter = "#{filter}&maxResults=#{maxresults}&startAt=#{ticket_count}"
  response = RestClient.get(jira_url + newfilter)
  raise 'Error with the http request!' if response.code != 200

  data = JSON.parse(response.body)
  # puts "current data is #{data}"
  # find the number of tickets returned
  total_issues = data['total']

  data['issues'].each do |issue|
    points = issue['fields']['customfield_10005']
    points = points.to_i
    issuekey = issue['key']
    summary = issue['fields']['summary']
    # substitute apostrophe for quote
    unless summary.nil?
      temp = summary.tr('"', "\'")
      summary = temp
    end
    desc = issue['fields']['description']
    # substitute apostrophe for quote
    unless desc.nil?
      temp = desc.tr('"', "\'")
      desc = temp
    end
#    puts "issue is #{issue['id']} key is #{issue['key']}" 

    # see if it has a parent, and if so, display it"
    parent = if !issue['fields']['parent'].nil?
               issue['fields']['parent']['key']
             else
               "#{issuekey}."
             end
    # what is the status?
    status = issue['fields']['status']['name']
    # puts "status is #{status}"

    # calculate the sprint by breaking the "sprint=" out of the sprint attributes string
    sprintdata = issue['fields']['customfield_10007']
    if sprintdata != nil
      idstring = sprintdata[0]
      sprintid = idstring['name']
    else
      sprintid = ''
    end

    # get type
    issuetype = if !issue['fields']['issuetype'].nil?
                  issue['fields']['issuetype']['name']
                else
                  ''
                end

    # get assignee
    assignee = if !issue['fields']['assignee'].nil?
                 issue['fields']['assignee']['name']
               else
                 ''
               end

    # get fixver
    if (issue['fields']['fixVersions'].length > 0) then
      fixverstring = issue['fields']['fixVersions'][0]
      fixver = fixverstring['name']
    else
      fixver = ''
    end

    # get component
    if (issue['fields']['components'].length > 0) then
      components = issue['fields']['components'][0]
      component = components['name']
    else
      component = ''
    end
    # puts "component is #{component}"
 
    # if this is the first output, then open the file with the sprintname and write the header
    if (ticket_count == 0) then
      # first create two .csv files - one with the parent appended, the other without - ensure the field names are OK
      filesprint = sprintid.gsub(" ","_")
      filesprint = filesprint.gsub("__","_")
      puts " old #{pullfile}"
      if pullfile == 'test.csv'
        pullfile =  "currentpull#{filesprint}.csv"
      end
      puts " new #{pullfile}"
      $parentpullfile = File.open(pullfile, 'w')
      $parentpullfile.puts('Issue id,Parent id,Summary,Issue Type,Story Points,Sprint,Description,Assignee,Fix Version, Component, Status')
    end
    # write to files
    $parentpullfile.puts("#{issuekey},#{parent},\"#{parent}/#{summary} (#{issuekey})\",#{issuetype},#{points},#{sprintid},\"#{desc}\",#{assignee},#{fixver},#{component},#{status}")
    ticket_count = ticket_count + 1

  end # while there are still tickets
  puts "ticket count is #{ticket_count}"
end

# if there was a new directory, copy the file over
# now that we are done, send the output file to the proper output directory
if outputdir != ''
  finalpullfile = "#{outputdir}#{pullfile}"
  FileUtils.cp(pullfile,finalpullfile)
end
