#! /usr/bin/env ruby

# frozen_string_literal: true

require 'rest-client'
require 'json'
require 'fileutils'
require 'optparse'
require 'logger'

logger = Logger.new($stdout)
logger.level = Logger::INFO
logger.formatter = proc do |severity, _datetime, _progname, msg|
  "#{severity}: #{msg}\n"
end

days = nil
sprint_number = nil
output_dir = 'jira_pulls_output'
output_filename = nil

OptionParser.new do |opts|
  opts.banner = 'Usage: jira_pull [options] (default will pull only the current sprint)'
  opts.on('-h', '--help', 'Help') do
    puts opts
    exit
  end
  opts.on('-s', '--sprint NUMBER', 'Sprint') do |s|
    sprint_number = s.strip
  end
  opts.on('-d', '--days NUMBER', 'number of days') do |d|
    days = d.strip
    output_filename = "tix_closed_#{days}.csv"
  end
  opts.on('-o', '--output DIR', 'Output Dir (full path)') do |o|
    puts "outdir is #{o}"
    output_dir = o.strip
  end
  opts.on('--debug') do
    logger.level = Logger::DEBUG
  end
end.parse!

FileUtils.mkdir_p(output_dir) unless File.directory?(output_dir)

# here is our jira instance
jira_url = 'https://simp-project.atlassian.net/rest/api/2/search?'

# create query
if sprint_number
  filter = "jql=sprint=#{sprint_number}"
  output_filename = "Sprint_#{sprint_number}.csv"
elsif days
  filter = %(jql=updated>-#{days}d)
  output_filename = %(Past_#{days}_Days_#{Time.now.strftime('%Y-%m-%d')}.csv)
else
  filter = 'jql=sprint in openSprints()'
  output_filename = nil
end

Dir.chdir(output_dir) do
  total_tickets = 1
  ticket_count = 0
  maxresults = 50

  output_header = [
    [
      'Issue id',
      'Parent id',
      'Summary',
      'Issue Type',
      'Story Points',
      'Sprint',
      'Description',
      'Assignee',
      'Fix Version',
      'Component',
      'Status'
    ]
  ]

  output_rows = []

  sprint_id = nil

  # while we have tickets still
  while ticket_count < total_tickets

    # call the code
    new_filter = "#{jira_url}#{filter}&maxResults=#{maxresults}&startAt=#{ticket_count}"
    logger.info("Query is #{new_filter}")

    response = RestClient.get(new_filter)

    unless response.code == 200
      logger.error("Error with HTTP request: #{response}")
      exit 1
    end

    data = JSON.parse(response.body)

    # find the number of tickets returned
    total_tickets = data['total']

    if total_tickets.to_i.positive?
      logger.debug("Processing #{total_tickets} issues")
    else
      logger.error('Did not find any issues to process, exiting')
      exit 1
    end

    data['issues'].each do |issue|
      fields = issue['fields']

      next unless fields

      issue_key = issue['key']
      logger.debug("Processing #{issue['key']} => #{issue['id']}")

      assignee = fields.dig('assignee', 'name')
      desc = fields['description']
      issue_type = fields.dig('issuetype', 'name')
      parent = fields.dig('parent', 'key') || "#{issue_key}."
      points = fields['customfield_10005']&.to_i
      status = fields.dig('status', 'name')
      summary = fields['summary']

      component = fields['components'].first
      component = component['name'] if component

      fix_version = fields['fixVersions'].first
      fix_version = fix_version['name'] if fix_version

      sprint_data = fields['customfield_10007']

      if sprint_data
        sprint_id ||= sprint_data.first['name']
        output_filename ||= "#{sprint_id.gsub(/\s+/, '_')}.csv"
      end

      output_rows << [
        issue_key,
        parent,
        %{#{parent}/#{summary} (#{issue_key})},
        issue_type,
        points,
        sprint_id,
        desc,
        assignee,
        fix_version,
        component,
        status
      ]

      ticket_count += 1
    end

    # while there are still tickets
    logger.info("Processed #{ticket_count} of #{total_tickets}")
  end

  if output_rows.count.zero?
    logger.error("No data found, not writing to '#{output_filename}'")
    exit 1
  end

  File.open(output_filename, 'w') do |fh|
    require 'csv'
    fh.puts(
      (output_header + output_rows.sort_by(&:first)).map do |r|
        r.to_csv(force_quotes: true)
      end.join
    )
  end
end
