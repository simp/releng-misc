#!/usr/bin/env ruby
# frozen_string_literal: true

################################################################################
#
# create_tix
# reads in a csv file
# creates a series of jira tickets based on column entries
# -f input file
# -p project (defaults to 'JJTEST', use `-p SIMP` when ready to do it live)
#
################################################################################

require 'csv'
require 'rest-client'
require 'json'
require 'optparse'

# match a jira ticket's parent or blocker from original file to get jira id
def find_ticket(tikid)
  found = false
  # puts " number of tix is #{@tickets.length}"
  if @tickets.length.positive?
    @tickets.each do |ticket_entry|
      tickno = ticket_entry['ticket_id']
      next unless tickno == tikid

      # if we found something, send it back
      found = true
      return ticket_entry['jira_id']
    end
  end
  return nil if found == false
end

def to_ascii(x)
  #Depending on how the table is pulled from confluence it can have
  #non Ascii characters in it.  Some of the fields in JIRA don't like this
  #and the ticket creation will fail. This removes non-ascii characters from
  #a string.
  encoding_options = {
    :invalid           => :replace,  # Replace invalid byte sequences
    :undef             => :replace,  # Replace anything not defined in ASCII
    :replace           => '',        # Use a blank for those replacements
    :universal_newline => true       # Always break lines with \n
  }

  x.encode(Encoding.find('ASCII'), encoding_options)
end

# initialize
@jira_id = ''
inputfile = 'test.csv'
outputfile = 'test_tickets.csv'
lines = 0
userid = ENV['JIRA_API_TOKEN'] or raise("Env var JIRA_API_TOKEN not set!  (ex: 'me@here.com:123456789012')")
resultfile = 'putresult.json'
allresultsfile = File.open('allresults.output', 'w')

@tickets = Array.new { {} }


# initialize the OSes in an array
os_type = ['', '', '', '', '', '', 'EL7', 'EL8', 'OEL7', 'OEL8', 'RHEL7', 'RHEL8']
jira_proj = 'JJTEST'
label = ''
dryrun = false

# get the filename and project if input by the user
optsparse = OptionParser.new do |opts|
  opts.banner = 'Usage: create_tickets [options]'
  opts.on('-f', '--input FILE', 'Input CSV file or directory of CSV files') do |f|
    inputfile = f.strip
  end
  opts.on('-p', '--project PROJECT', "Jira Project to create tickets (#{jira_proj})") do |s|
    jira_proj = s.strip
  end
  opts.on('-d', '--dry-run', 'Do not perform the ticket creation just output commands to the command file') do
    dryrun = true
  end
  opts.on('-l', '--label LABEL', "Label to place on tickets (#{label}) ") do |s|
    label = s.strip
  end
  opts.on('-h', '--help', 'Help') do
    puts opts
    exit
  end
end
optsparse.parse!

# set up output file
outfile = File.open(outputfile, 'w')
outfile.puts('Ticket, Summary, Description, Component, Blocker, Points, Parent, Jira ID')

# also write commands to a file in case it does not work, then we can try it mnaually to find the problem
cmdfile = File.open('commands.txt', 'w')

# set up input file
# CSV.foreach(inputfile, 'r:bom|utf-9') do |col|
CSV.foreach(inputfile) do |col|
  type = 'Story'
  points = 0

  begin
    # get out the fields we need
    ticket_id = col[0]
    summary = col[1]
    descr = col[2]
    component = to_ascii(col[3]).strip
    blocker = col[4]
    points = col[5].to_i
    blocker_id = nil
    parent_id = nil

    # in case we need to edit description
    mydesc = descr

    # if no point value, make it zero
    points = 0 if points.nil?

    # see if the ticket ID has "." - if so it is a sub-task, if not, it is a task
    unless ticket_id.nil?
      if ticket_id.include? '.'
        type = 'Sub-task'
        parent_id = ticket_id[0..ticket_id.index('.') - 1]
        # puts "parent_id is #{parent_id}"
      else
        type = 'Story'
        parent_id = ''
      end
    end
    # puts "ID is #{ticket_id}, parent is #{parent_id}"

    # summary - clean out values that will mess up the string
    summary = summary.gsub("\n", ' ')
    summary = summary.gsub("\'", '')
    summary = summary.gsub("\r", '')
    summary = summary.gsub('{', '')
    summary = summary.gsub('}', '')
    summary = summary.gsub('\"', '')

    # description - clean out values that will mess up the string
    unless mydesc.nil?
      mydesc = mydesc.gsub("\'", '')
      mydesc = mydesc.gsub("\r", '')
      mydesc = mydesc.gsub('{', '')
      mydesc = mydesc.gsub('}', '')
      mydesc = mydesc.gsub('\"', '')
      mydesc = mydesc.gsub("\n", ' ')
    end

    # if the summary field is too long, we gotta move it over to the description
    if summary.size > 90
      summ = "#{summary[0..80]}..."
      mydesc = "#{summary}-#{mydesc}"
    else
      summ = summary
    end

    # check which O/Ses we're doing (if none found, make a generic ticket)
    foundone = false
    (6..11).each do |os|
      command_created = false
      if !col[os].nil? && ((col[os] == 'Y') || (col[os] == 'y'))
        prefix = os_type[os]
        summ_os = "#{prefix} - #{summ}"
        foundone = true
        command_created = true
      else
        summ_os = summ
      end

      # that last column does not exist, but just seeing if we had an O/S checked
      # if not, just do a ticket with no O/S
      command_created = true if (os == 11) && (foundone == false)

      # if it is a subtask find its parent's id
      if type == 'Story'
        parentid = nil
        subtask = false
      else
        subtask = true
        parentid = find_ticket(parent_id)
      end

      # blockers later...
      blocker_id = find_ticket(blocker)

      # skip header line!
      command_created = true if component == 'Component'

      # if we set up a command, let's do it
      next unless (command_created == true) && (component != 'Component')

      #    puts "component=#{component}, summary=#{summ_os}, desc=#{mydesc}, points=#{points}, type=#{type}"

      # set up output line
      json_line = "{\"fields\":{\"project\":{\"key\":\"#{jira_proj}\"}"
      json_line += ",\"issuetype\":{\"name\":\"#{type}\"}"
      json_line += ",\"customfield_10005\":#{points}"
      json_line += ",\"summary\":\"#{summ_os}\""
      unless mydesc.nil?
        json_line += ',"description":{"version":1,"type":"doc","content":[{"type":"paragraph"'
        json_line += ",\"content\":[{\"type\":\"text\",\"text\":\"#{mydesc}\"}]}]}"
      end
      if !component.nil? and !component.empty?
        json_line += ",\"components\":[{\"name\":\"#{component}\"}]"
      end
      json_line += ",\"labels\":[\"#{label}\"]" unless label.empty?
      json_line += ",\"parent\":{\"key\":\"#{parentid}\"}" if subtask == true
      blocker_line = ',"update":{"issuelinks":[{"add":'
      blocker_line += '{"type":{"name":"Blocks","inward":"is blocked by","outward":"blocks"},'
      blocker_line += "\"inwardIssue\":{\"key\":\"#{blocker_id}\"}}}]"
      json_line = if blocker_id.nil?
                    "#{json_line}}"
                  else
                    "#{json_line}}#{blocker_line}"
                  end
      json_line += '}}'

      # here is our jira instance
      jira_id = "NOT#{jira_proj}-#{ticket_id}"
      page_url = 'https://simp-project.atlassian.net/rest/api/3/issue'
      options = " --user #{userid} --header 'Accept: application/json' --header 'Content-type: application/json'"
      data_fields = "--data '#{json_line}'"
      # (changed to silent - undo for debug) cmd = "curl -v --request POST --url '#{page_url}' #{options} #{data_fields} > #{resultfile}"
      cmd = "curl -s -v --request POST --url '#{page_url}' #{options} #{data_fields} > #{resultfile}"

      # save the command (if it fails we can try it manually)
      cmdfile.puts "#{cmd}\n\n"
      unless dryrun
        exit_val = system(cmd)
        if exit_val == true
          File.open(resultfile).each do |row|
            puts row
            jsonrow = JSON.parse(row)
            jira_id = jsonrow['key']
            puts "Your ticket is #{jsonrow['id']}, ticket #{jira_id}"
          end
        else
          puts "command failed (check #{resultfile})"
        end
        puts "jira_id is #{jira_id}"

        # append results file in case we need to look for fails
        last_results = File.read(resultfile)
        allresultsfile.puts last_results
      end

      # save the parameters for later
      tickethash = {}
      tickethash['ticket_id'] = ticket_id
      tickethash['type'] = type
      tickethash['summary'] = summ_os
      tickethash['descr'] = descr
      tickethash['component'] = component
      tickethash['blocker'] = blocker
      tickethash['blocker_id'] = blocker_id
      tickethash['points'] = points
      tickethash['jira_id'] = jira_id
      tickethash['parent'] = parentid
      @tickets << tickethash
      lines += 1

      # success
      outfile.puts("#{ticket_id},\"#{summ_os}\",\"#{mydesc}\",#{component},#{blocker_id},#{points}," \
                   "#{parentid},#{jira_id},")
    end
  rescue StandardError => e
    puts("#{e.message} error on record with id #{ticket_id} - skipping")
  end
end
puts 'final tickets'
@tickets.each do |tic|
  puts tic
end

allresultsfile.close
# while
