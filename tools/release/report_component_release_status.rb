#!/usr/bin/env ruby
#
require 'fileutils'
require 'json'
require 'optparse'

class ComponentStatusReporter

  class ParseFailure < RuntimeError; end

  COMPONENT_SEPARATOR      = "\n" + '<'*3 + '#'*80 + '>'*3 + "\n"
  INFO_SEPARATOR           = "\n" + '^'*80 + "\n"

  def initialize
    @options = {
      :input_file              => 'component_release_summary.txt',
#      :output_file             => 'component_release_status.txt',
      :report_errors           => true,
      :report_tag_required     => true,
      :report_tag_current      => false,
      :print_tag_status        => false, # since default is to only report
                                         # errors and new tag required projects,
                                         # this extra column is meaningless
      :verbose                 => false,
      :help_requested          => false
    }
  end

  def parse_command_line(args)
    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename(__FILE__)} [options]"
      opts.separator ''

      opts.on(
        '-i', '--infile INFILE',
        'Input file containing raw results to be summarized.',
        "Defaults to #{@options[:input_file]}"
      ) do |input_file|
        @options[:input_file] = File.expand_path(input_file)
      end

=begin
NOT YET IMPLEMENTED
      opts.on(
        '-o', '--outfile OUTFILE',
        "Summary file. Defaults to #{@options[:output_file]}"
      ) do |output_file|
        @options[:output_file] = File.expand_path(output_file)
      end
=end

      opts.on(
        '--[no-]report-errors',
        'Report components for which the latest changelog',
        "could not be extracted. Defaults to #{@options[:report_errors]}."
      ) do |report_errors|
        @options[:report_errors] = report_errors
      end

      opts.on(
        '--[no-]report-tag-required',
        'Report components for which a new tag is required.',
        "Defaults to #{@options[:report_tag_required]}."
      ) do |report_tag_required|
        @options[:report_tag_required] = report_tag_required
      end

      opts.on(
        '--[no-]report-tag-current',
        'Report components for which a the latest tag is current.',
        "Defaults to #{@options[:report_tag_current]}."
      ) do |report_tag_current|
        @options[:report_tag_current] = report_tag_current
        @options[:print_tag_status] = true if report_tag_current
      end

      opts.on(
        '-v', '--verbose',
        'Print all commands executed'
      ) do
        @options[:verbose] = true
      end

      opts.on( "-h", "--help", "Print this help message") do
        @options[:help_requested] = true
        puts opts
      end
    end


    begin
      opt_parser.parse!(args)
    rescue RuntimeError,OptionParser::ParseError => e
      raise "#{e.message}\n#{opt_parser.to_s}"
    end
  end

  def collate_results(component_results)
    header = [ '*Component*', '*Git Ref*', '*Version*', '*Tag Status*',
      '*Changelog*' ]

    # as a first pass, just gather the component results to be reported
    relevant_results = []
    component_results.each do |result|
      next if skip_status?(result[:tag_status])

      relevant_results << [
        result[:url].split('/').last,
        result[:git_ref],
        result[:version],
        result[:tag_status],
        result[:changelog].strip.split("\n")
      ]
    end

    # as a second pass, insert header and component separators, and
    # split each component changelog line into its own entry
    separator        = Array.new(header.size, :separator)
    header_separator = Array.new(header.size, :header)

    summary_results = []
    summary_results << separator
    summary_results << header
    summary_results << header_separator

    relevant_results.each do |result|
      # insert component info + changelog 1st line on 1st line
      # and then subsequent lines with just changelog info
      result[4].each_index do |index|
        if index == 0
          summary_results << [
            result[0],        # name
            result[1],        # git_ref
            result[2],        # version
            result[3].to_s,   # tag_status
            result[4][index]  # 1st line of changelog
          ]
        else
          summary_results << [
            ' '*result[0].size, # name placeholder
            ' '*result[1].size, # git_ref placeholder
            ' '*result[2].size, # version placeholder
            ' '*result[3].size, # tag_status placeholder
            result[4][index]    # next line of changelog
          ]
        end
      end
      # insert separator
      summary_results << separator
    end

    summary_results
  end

  def skip_status?(tag_status)
    ((tag_status == :released)   and !@options[:report_tag_current])  or
    ((tag_status == :unreleased) and !@options[:report_tag_required]) or
    ((tag_status == :error)      and !@options[:report_errors])
  end

  def output_status_summary(component_results)
    summary_results = collate_results(component_results)
    num_fields = summary_results[0].size

    # determine maximum field sizes for pretty printing of results
    max_lengths = Array.new(num_fields, 0)
    summary_results.each do |result|
      puts "Processing  #{result}" if @options[:verbose]
      next if (result[0] == :header) or (result[0] == :separator)

      (0..(num_fields-1)).each do |index|
        result[index] = '---' if result[index].nil?
        if max_lengths[index] < result[index].size
          max_lengths[index] = result[index].size
        end
      end
    end

    # create header and component line delimiters
    header_delimiter = ''
    component_delimiter = ''
    max_lengths.each_index do |index|
      if (index != 3) or @options[:print_tag_status]
        header_delimiter << '+' << '='*(max_lengths[index]+2)
        component_delimiter << '+' << '-'*(max_lengths[index]+2)
      end
    end
    header_delimiter <<  '+'
    component_delimiter <<  '+'

    separater_count = 0
    summary_results.each do |result|
      if result[0] == :separator
        puts component_delimiter
      elsif result[0] == :header
        puts header_delimiter
      else
        print '|'
        result.each_index do |index|
           if (index != 3) or @options[:print_tag_status]
             print " #{result[index].ljust(max_lengths[index], ' ')} |"
           end
        end
        puts
      end
    end
  end

  def parse_component_status_log(component_log)
    match = component_log.match(/Processing (\S+) (\S+) ref=(\S+)/)
    unless match
      raise ParseFailure.new("Unable to parse component info in '#{component_log.split("\n")[0]}'")
    end

    puts "Gathering status results for #{match[1]}" if @options[:verbose]

    status = component_log.split(INFO_SEPARATOR)
    # remove component info lines
    status.shift
    unless status.size == 2
      raise ParseFailure.new("Unable to parse status info in '#{component_log.split("\n")[0]}'")
    end

    version, changelog = parse_changelog_status(status[1])
    results = {
        :component  => match[1],
        :url        => match[2],
        :git_ref    => match[3],
        :version    => version,
        :tag_status => parse_tag_status(status[0]),
        :changelog  => changelog
    }

    # manually fix released components that have bad changelogs
    # TODO remove this when we no longer have bad changelogs
    if results[:component] == 'upstart' and results[:tag_status] == :error
       results[:version]    = '6.0.1'
       results[:tag_status] = :released
       results[:changelog]  = 'unknown'
    end

    results
  end

  def parse_tag_status(tag_status_log)
    tag_status = :unknown
    if tag_status_log.include?('No new tag required')
      tag_status = :released
    elsif tag_status_log =~ /New tag of version '.*' is required/
      tag_status = :unreleased
    elsif tag_status_log.include?('rake aborted!')
      tag_status = :error
    end
    tag_status
  end

  def parse_changelog_status(changelog_status_log)
    version = 'unknown'
    changelog = 'FIXME: changelog validation failed'
    match = changelog_status_log.match(/Release of (\S+)/)
    if match
      version = match[1]
      changelog = changelog_status_log.strip
    end
    return [version, changelog]
  end

  def run(args)
    parse_command_line(args)
    return 0 if @options[:help_requested] # already have logged help

    # break log into per-component logs, removing any general info logged at
    # the beginning and end of the status generation
    log = IO.read(@options[:input_file])
    component_logs = log.split(COMPONENT_SEPARATOR).delete_if { |entry| entry.strip.empty? }
    [0, -1].each do |index|
      component_logs.delete_at(index) unless component_logs[index] =~ /^Processing /
    end

    # parse component status results from the logs
    component_results = component_logs.map do |component_log|
      parse_component_status_log(component_log)
    end

    output_status_summary(component_results)
    return 0
  rescue SignalException =>e
    if e.inspect == 'Interrupt'
      $stderr.puts "\nProcessing interrupted! Exiting."
    else
      $stderr.puts "\nProcess received signal #{e.message}. Exiting!"
      e.backtrace.first(10).each{|l| $stderr.puts l }
    end
    return 1
  rescue RuntimeError =>e
    $stderr.puts("ERROR: #{e.message}")
    return 1
  rescue => e
    $stderr.puts("\n#{e.message}")
    e.backtrace.first(10).each{|l| $stderr.puts l }
    return 1
  end

end

####################################
if __FILE__ == $0
  reporter = ComponentStatusReporter.new
  exit reporter.run(ARGV)
end
