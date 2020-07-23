#!/usr/bin/env ruby
require 'optparse'

class AcceptanceTestReportGenerator

  class ParseFailure < RuntimeError; end

  DEFAULT_VERBOSE       = false
  DEFAULT_PRETTY_STATUS = false

  def initialize
   @verbose = DEFAULT_VERBOSE
   @pretty_status = DEFAULT_PRETTY_STATUS
   @log_files = []
   @help_requested = false
  end

  # These separators are set by AcceptanceTestRunner
  COMPONENT_SEPARATOR      = "\n" + '<'*3 + '#'*80 + '>'*3 + "\n"
  TEST_SEPARATOR           = "\n" + '^'*80 + "\n"

  def format_status(status)
    status = :unknown if status.nil?
    formatted_status = status.to_s.upcase
    if @pretty_status
      case status
      when :passed  # bold green
        formatted_status = '{color:#14892c}*' + formatted_status + '*{color}'
      when :failed  # bold red
        formatted_status = '{color:#d04437}*' + formatted_status + '*{color}'
      when :unknown # bold yellow
        formatted_status = '{color:#f6c342}*' + formatted_status + '*{color}'
      else # bold orange
        formatted_status = '{color:#f79232}*' + formatted_status + '*{color}'
      end
    end
    formatted_status
  end

  def parse_component_test_logs(raw_results)
    if raw_results.match(/^No acceptance tests for/)
      results = parse_results_without_tests(raw_results)
    elsif raw_results.match(/^Processing .* version=/)
      results = parse_results_with_tests(raw_results)
    else
      raise ParseFailure.new("Unable to find test results for record beginning with\n #{raw_results.split("\n")[0]}")
    end
  end

  def parse_results_without_tests(raw_results)
    match = raw_results.match(/No acceptance tests for (\S+) version=(\S+) \S+ ref=(\S+)/)
    unless match
      raise ParseFailure.new("Unable to parse component info in ' #{raw_results.split("\n")[0]}'")
    end
    puts "Gathering test results for #{match[1]}" if @debug

    results = {
        :component => match[1],
        :version   => match[2],
        :git_ref   => match[3]
    }
    results
  end

  def parse_results_with_tests(raw_results)
    match = raw_results.match(/Processing (\S+) version=(\S+) \S+ ref=(\S+)/)
    unless match
      raise ParseFailure.new("Unable to parse component info in ' #{raw_results.split("\n")[0]}'")
    end
    puts "Gathering test results for #{match[1]}" if @debug

    results = {
        :component => match[1],
        :version   => match[2],
        :git_ref   => match[3],
        :tests     => parse_tests(raw_results)
    }
    results
  end

  def parse_tests(raw_results)
    results = []
    tests = raw_results.split(TEST_SEPARATOR)
    # remove any segment that isn't a test
    tests.delete_if { |entry| !entry.include?(' bundle exec rake ') }

    tests.each do |test_output|
      test_id_match = test_output.match(/PUPPET_VERSION=(\S+) (?:(.*) ){0,1}bundle exec rake (?:acceptance|(?:beaker:suites\[(\S+)\]))/)
      unless test_id_match
        fail("Parse failure:  Test parsing failed for record beginning with\n  Executing: #{test_output.split("\n")[0]}")
      end

      results << {
        :puppet_version => test_id_match[1],
        :fips           => is_fips_enabled(test_id_match[2]),
        :test_name      => test_id_match[3].nil? ? 'default' : test_id_match[3],  # nil if bundle exec rake acceptance
        :result         => get_test_status(test_output)
      }
    end
    results
  end

  def is_fips_enabled(beaker_options)
    fips_enabled = false
    if beaker_options and beaker_options.include?('BEAKER_fips=yes')
      fips_enabled = true
    end
    return fips_enabled
  end

  def get_test_status(test_output)
    match = test_output.match(/\n(([0-9]+) example(?:s{0,1}), ([0-9]+) failure(?:s{0,1}(.*)))\n/)
    return [format_status(:unknown), 'No results found'] if match.nil?

    test_result = match[1]
    examples = match[2].to_i
    failures = match[3].to_i
    #other = match[4]  # this can contain pending examples or the text
    #                  # about failures outside of examples

    if examples != 0 and failures == 0
      return [ format_status(:passed), test_result ]
    else
      return [ format_status(:failed), test_result ]
    end
  end

  def collate_results(test_results)
    header = [ '*Component*', '*Git Ref*', '*Version*',
      '*Test Name*', '*FIPS*', '*Status*', '*Detail*' ]

    summary_results = []

    test_results.each do |results|
      if results[:tests]
        common_info = [
          results[:component],
          results[:git_ref],
          results[:version]
        ]
        results[:tests].each do |test|
          test_info = [
            common_info,
            test[:test_name],
            test[:fips] ? 'FIPS' : 'no FIPS',
            test[:result]
          ].flatten
          # strip out bad results from old error in run_acceptance_tests.rb
          next if test[:puppet_version].include?('{puppet_version}')
          summary_results << test_info
        end
      else
        summary_results << [
          results[:component],
          results[:git_ref],
          results[:version],
        ]
      end
    end

    fail('No test results found') if summary_results.empty?
    summary_results.uniq!
    summary_results.sort! do |left,right|
      #component name + test (if it exists) + fips (if it exists)
      max_name_length = left[0].size > right[0].size ? left[0].size : right[0].size
      max_test_name_length = left[3].to_s.size > right[3].to_s.size ? left[3].to_s.size : right[3].to_s.size
      left_string = [
        left[0].ljust(max_name_length, ' '),
        left[3].to_s.ljust(max_test_name_length, ' '),
        left[4].to_s
      ].join
      right_string = [
        right[0].ljust(max_name_length, ' '),
        right[3].to_s.ljust(max_test_name_length, ' '),
        right[4].to_s
      ].join
      left_string <=> right_string
    end
    [header, summary_results]
  end

  def output_results(test_results)
    header, summary_results = collate_results(test_results)

    # determine maximum field sizes for pretty printing of results
    max_lengths = Array.new(header.size, 0)
    puts "max_lengths=#{max_lengths}" if @debug
    summary_results.unshift(header)
    summary_results.each do |result|
      puts "Processing  #{result}" if @debug

      header.each_index do |index|
        result[index] = '---' if result[index].nil?
        max_lengths[index] = (max_lengths[index] >= result[index].size) ? max_lengths[index] : result[index].size
      end
    end

    # pretty print table in format suitable for JIRA
    summary_results.each do |result|
      print '|'
      result.each_index do |index|
         print " #{result[index].ljust(max_lengths[index], ' ')} |"
      end
      puts
    end
  end

  def parse_command_line(args)
    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename(__FILE__)} [options] LOG1 [LOG2 ...]"
      opts.separator ''
      opts.on(
        '-p', '--pretty-status',
        "Colorizes test status for JIRA reporting. Defaults to #{DEFAULT_PRETTY_STATUS}."
      ) do
        @pretty_status = true
      end

      opts.on(
        '-v', '--verbose',
        "Print debug information. Defaults to #{DEFAULT_VERBOSE}."
      ) do
        @debug = true
      end

      opts.on( "-h", "--help", "Print this help message") do
        @help_requested = true
        puts opts
      end
    end

    begin
       @log_files = opt_parser.parse!(args)
       unless @help_requested
         raise "No log files specified" if @log_files.empty?
       end
    rescue OptionParser::ParseError => e
      raise "#{e.message}\n#{opt_parser.to_s}"
    end
  end

  def run(args)
    parse_command_line(args)
    return 0 if @help_requested # already have logged help

    test_results = []
    @log_files.each do |logfile|
      # read in log and remove bash color encoding
      log = IO.read(logfile).gsub(/\x1B\[(([0-9]+)(;[0-9]+)*)?[m,K,H,f,J]/, '')

      # break log into per-component logs, removing any general info logged at
      # the beginning of the test run
      component_test_logs = log.split(COMPONENT_SEPARATOR).delete_if { |entry| entry.strip.empty? }
      component_test_logs.shift unless log.start_with?(COMPONENT_SEPARATOR)

      # parse component test results from the logs
      test_results << component_test_logs.map  { |component_log|  parse_component_test_logs(component_log) }
    end

    output_results(test_results.flatten)
    return 0

  rescue ParseFailure => e
    $stderr.puts("Parse Failure: #{e.message}")
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
  reporter = AcceptanceTestReportGenerator.new
  exit reporter.run(ARGV)
end

