#!/usr/bin/env ruby
#
require 'fileutils'
require 'json'
require 'optparse'

=begin
output should be
|component | version in proposed | version in last | last released version,| URL to changelog on master |
|          | puppetfile proposed | SIMP release    | latest version        |                            |
=end

# parts lifted from simp-rake-helpers R10KHelper
class PuppetfileHelper
  attr_accessor :puppetfile
  attr_accessor :modules
  attr_accessor :basedir

  require 'r10k/puppetfile'

  def initialize(puppetfile)
    @modules = []
    @basedir = File.dirname(File.expand_path(puppetfile))

    Dir.chdir(@basedir) do

      R10K::Git::Cache.settings[:cache_root] = File.join(@basedir,'.r10k_cache')
      FileUtils.mkdir_p(R10K::Git::Cache.settings[:cache_root])

      r10k = R10K::Puppetfile.new(Dir.pwd, nil, puppetfile)
      r10k.load!

      @modules = r10k.modules.collect do |mod|
        mod = {
          :name        => mod.name,
          :path        => mod.path.to_s,
          :remote      => mod.repo.instance_variable_get('@remote'),
          :desired_ref => mod.desired_ref,
          :git_source  => mod.repo.repo.origin,
          :git_ref     => mod.repo.head,
          :module_dir  => mod.basedir,
          :r10k_module => mod
        }
      end
    end
  end

  def each_module(&block)
    Dir.chdir(@basedir) do
      @modules.each do |mod|
        block.call(mod)
      end
    end
  end

end

class ComponentStatusGenerator

  class InvalidModule < StandardError; end

  COMPONENT_SEPARATOR      = "\n" + '<'*3 + '#'*80 + '>'*3 + "\n"
  INFO_SEPARATOR           = "\n" + '^'*80 + "\n"

  SIMP_RSPEC_PUPPET_FACTS_VERSION = '~> 2.0'
  SIMP_RAKE_HELPERS_VERSION       = '~> 5'

  RAKE_ENV = {
    :simp_rspec_puppet_facts_version => SIMP_RSPEC_PUPPET_FACTS_VERSION,
    :simp_rake_helpers_version       => SIMP_RAKE_HELPERS_VERSION
  }

  CHANGELOG_EXEC   = 'bundle exec rake pkg:create_tag_changelog'
  COMPARE_TAG_EXEC = 'bundle exec rake pkg:compare_latest_tag'

  def initialize
    env_str = ''
    RAKE_ENV.each do |key,value|
      env_str << "#{key.to_s.upcase}='#{value}' "
    end

    @options = {
      :env_str                 => env_str,
      :root_dir                => File.expand_path('.'),
      :output_file             => 'component_release_status.txt',
      :clean_start             => true,
      :skip_bundle_update      => false,
      :dry_run                 => false,
      :verbose                 => false,
      :help_requested          => false
    }
  end

  def check_out_projects
    info('Preparing a clean projects checkout')

    # make sure we are starting clean
    Dir.chdir(@options[:root_dir]) do
      execute("bundle exec rake deps:clean", @options[:verbose])
      execute("#{@options[:env_str]} bundle update", false)
      execute("#{@options[:env_str]} bundle exec rake deps:checkout", @options[:verbose])
    end
  end

  def execute(command, log_command=true)
    info("Executing: #{command}") if log_command
    result = nil
    unless @options[:dry_run]
      result = `#{command} 2>&1 | egrep -v 'warning: already initialized constant|warning: previous definition|internal vendored libraries are Private APIs and can change without warning'`
    end
    result
  end

  def get_git_info
    git_status = `git status`.split("\n").delete_if do |line|
      line.match(/HEAD detached at|On branch/).nil?
    end
    git_revision = git_status[0].gsub(/# HEAD detached at |# On branch /,'')
    git_origin_line = `git remote -v`.split("\n").delete_if do |line|
      line.match(/^origin/).nil? or line.match(/\(fetch\)/).nil?
    end
    git_origin = git_origin_line[0].gsub(/^origin/,'').gsub(/.fetch.$/,'').strip
    [git_origin, git_revision]
  end

  def get_project_list
    projects = get_assets
    projects << get_simp_owned_modules
    projects.flatten
  end

  def get_simp_owned_modules
    modules_dir = File.join(@options[:root_dir], 'src', 'puppet', 'modules')
    simp_modules = []

    # determine all SIMP-owned modules
    modules = Dir.entries(modules_dir).delete_if { |dir| dir[0] == '.' }
    modules.sort.each do |module_name|
      module_path = File.join(modules_dir, module_name)
      begin
        metadata = load_module_metadata(module_path)
        if metadata['name'].split('-')[0] == 'simp'
          simp_modules << module_path
        end
      rescue InvalidModule => e
        puts "Skipping invalid module: #{module_name}: #{e}"
      end
    end

    simp_modules.sort
  end

  def get_assets
    assets_dir = File.join(@options[:root_dir], 'src', 'assets')
    assets = Dir.entries(assets_dir).delete_if { |dir| dir[0] == '.' }
    assets.map! { |asset| File.join(@options[:root_dir], 'src', 'assets', asset) }
    assets.sort
  end


  def load_module_metadata( file_path = nil )
    require 'json'
    begin
      JSON.parse(File.read(File.join(file_path, 'metadata.json')))
    rescue => e
      raise InvalidModule.new(e.message)
    end
  end

  def debug(msg)
    log(msg) if @options[:verbose]
  end

  def info(msg)
    log(msg)
  end

  def log(msg)
    unless @log_file
      @log_file = File.open(@options[:output_file], 'w')
    end
    @log_file.puts(msg) unless msg.nil?
    @log_file.flush
  end

  def parse_command_line(args)

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename(__FILE__)} [options]"
      opts.separator ''

      opts.on(
        '-d', '--root-dir ROOT_DIR',
        'Root directory of simp-core checkout.',
        'Defaults to current directory.'
      ) do |root_dir|
        @options[:root_dir] = File.expand_path(root_dir)
      end

      opts.on(
        '-o', '--outfile OUTFILE',
        "Output file. Defaults to #{@options[:output_file]}"
      ) do |output_file|
        @options[:output_file] = File.expand_path(output_file)
      end


=begin
NEED TO IMPLEMENT FEATURE
      opts.on(
        '-t', '--[no-]report-changelog-errors',
        'Report components for which the latest changelog',
        "could not be extracted. Defaults to #{@options[:report_changelog_errors]}."
      ) do |report_changelog_errors|
        @options[:report_changelog_errors] = report_changelog_errors
      end
=end

=begin
NEED TO IMPLEMENT FEATURE
      opts.on(
        '-t', '--[no-]report-tag-required',
        'Report components for which a new tag is required.',
        "Defaults to #{@options[:report_tag_required]}."
      ) do |report_tag_required|
        @options[:report_tag_required] = report_tag_required
      end
=end

=begin
NEED TO IMPLEMENT FEATURE
      opts.on(
        '-t', '--[no-]report-tag-current',
        'Report components for which a the latest tag is current.',
        "Defaults to #{@options[:report_tag_current]}."
      ) do |report_tag_current|
        @options[:report_tag_current] = report_tag_current
      end
=end

      opts.on(
        '-s', '--[no-]clean-start',
        'Start with a fresh checkout of Puppet modules/assets.',
        'Existing module/asset directories will be removed.',
        "Defaults to #{@options[:clean_start]}."
      ) do |clean_start|
        @options[:clean_start] = clean_start
      end

      opts.on(
        '-b', '--skip-bundle-update',
        'Skips running bundle update in each component directory.',
      ) do
        @options[:skip_bundle_update] = true
      end

      opts.on(
        '-D', '--dry-run',
        "Print the commands to be run, but don't execute them.",
      ) do
        @options[:dry_run] = true
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
      @options[:skip_bundle_update] = false if @options[:clean_start]
    rescue RuntimeError,OptionParser::ParseError => e
      raise "#{e.message}\n#{opt_parser.to_s}"
    end
  ensure
    @log_file.close unless @log_file.nil?
  end

  def run(args)
    parse_command_line(args)
    return 0 if @options[:help_requested] # already have logged help

    info("Running with options = <#{args.join(' ')}>") unless args.empty?
    debug("Internal options=#{@options}")
    info("START TIME: #{Time.now}")

    load_proposed_puppetfile.

    check_out_projects if @options[:clean_start]


    results = {}
    get_project_list.each do |project_dir|
      Dir.chdir(project_dir) do
        project = File.basename(project_dir)
        git_origin, git_revision = get_git_info
        project_info = "#{project} #{git_origin} ref=#{git_revision}"

        info(COMPONENT_SEPARATOR)
        info("Processing #{project_info}")
        execute("#{@options[:env_str]} bundle update", false) unless @options[:skip_bundle_update]

        tag_result = execute("#{@options[:env_str]} #{COMPARE_TAG_EXEC}", @options[:verbose])
        info(INFO_SEPARATOR)
        info(tag_result)

        changelog = execute("#{@options[:env_str]} #{CHANGELOG_EXEC}", @options[:verbose])
        info(INFO_SEPARATOR)
        info(changelog)
      end
    end

    info(COMPONENT_SEPARATOR)
    info("STOP TIME: #{Time.now}")
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
  reporter = ComponentStatusGenerator.new
  exit reporter.run(ARGV)
end
