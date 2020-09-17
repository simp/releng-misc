#!/usr/bin/env ruby
#
require 'fileutils'
require 'json'
require 'optparse'
require 'parallel'
require 'r10k/git'
require 'yaml'

# parts lifted from simp-rake-helpers R10KHelper
class R10K::Git::ShellGit::ThinRepository
  def cache_repo
    @cache_repo
  end
end

class PuppetfileHelper
  attr_accessor :puppetfile
  attr_accessor :modules
  attr_accessor :basedir

  require 'r10k/puppetfile'

  def initialize(puppetfile, root_dir, purge_cache = true)
    @modules = []
    @gitlab_client = nil

    Dir.chdir(root_dir) do
      cache_dir = File.join(root_dir,'.r10k_cache')
      FileUtils.rm_rf(cache_dir) if purge_cache
      FileUtils.mkdir_p(cache_dir)
      R10K::Git::Cache.settings[:cache_root] = cache_dir

      r10k = R10K::Puppetfile.new(Dir.pwd, nil, puppetfile)
      r10k.load!

      @modules = r10k.modules.collect do |mod|
        mod = {
          :name        => mod.name,
          :path        => mod.path.to_s,
          :r10k_module => mod,
          :r10k_cache  => mod.repo.repo.cache_repo
        }
      end
    end
  end
end


class MetadataStatusGenerator

  class InvalidModule < StandardError; end

  def initialize

    @options = {
      :puppetfile              => nil,
      :root_dir                => File.expand_path('.'),
      :output_file             => 'simp_component_metadata_summary.csv',
      :clean_start             => true,
      :verbose                 => false,
      :help_requested          => false
    }
  end

  def check_out_projects
    debug("Preparing a clean projects checkout at #{@options[:root_dir]}")
    #FIXME the root directory for checkouts should be pulled from the Puppetfile
    FileUtils.rm_rf(File.join(@options[:root_dir], 'src'))

    helper = PuppetfileHelper.new(@options[:puppetfile], @options[:root_dir])
    Parallel.map( Array(helper.modules), :progress => 'Submodule Checkout') do |mod|
      Dir.chdir(@options[:root_dir]) do
        FileUtils.mkdir_p(mod[:path])

        # make sure R10K cache is current, as that is what populates R10K 'thin' git repos
        # used in the module sync operation
        #TODO do I need to do this?
        unless mod[:r10k_cache].synced?
          mod[:r10k_cache].sync
        end

        # checkout the module at the revision specified in the Puppetfile
        mod[:r10k_module].sync
      end
    end
  end

  def get_git_info
    git_ref = `git log -n 1 --format=%H`.strip
    git_origin_line = `git remote -v`.split("\n").delete_if do |line|
      line.match(/^origin/).nil? or line.match(/\(fetch\)/).nil?
    end
    git_origin = git_origin_line[0].gsub(/^origin/,'').gsub(/.fetch.$/,'').strip
    [git_origin, git_ref]
  end

  def get_modules_metadata
    #FIXME this directory should be pulled from the Puppetfile
    modules_dir = File.join(@options[:root_dir], 'src', 'puppet', 'modules')
    modules_metadata = {}

    return module_list unless Dir.exist?(modules_dir)
    modules = Dir.entries(modules_dir).delete_if { |dir| dir[0] == '.' }
    modules.sort.each do |module_name|
      module_path = File.expand_path(File.join(modules_dir, module_name))
      begin
        metadata = load_module_metadata(module_path)
        metadata[:module_path] = module_path
        if metadata['name'].split('-')[0] == 'simp'
          metadata[:simp_owned] = true
        else
          metadata[:simp_owned] = false
        end

        modules_metadata[metadata['name']] = metadata
      rescue InvalidModule => e
        warning("Skipping invalid module: #{module_name}: #{e}")
      end
    end

    modules_metadata
  end

  def get_os_versions(os, metadata)
    versions = [ :none ]
    if metadata.has_key?('operatingsystem_support')
      metadata['operatingsystem_support'].each do |os_hash|
        if os_hash.has_key?('operatingsystem') && (os_hash['operatingsystem'] == os)
          if os_hash['operatingsystemrelease']
            versions = os_hash['operatingsystemrelease'].sort
          else
            versions = [ :any ]
          end

          break
        end
      end
    end

    # NOTE: this doesn't detect skipped OS versions
    [ versions[0], versions[-1] ]
  end

  def get_puppet_versions(metadata)
    min = 'any'
    max = 'any'

    if metadata.has_key?('requirements')
      metadata['requirements'].each do |req|
        if req.has_key?('name') && req['name'] == 'puppet'
          version_string = req['version_requirement']

          # FIXME this min/max logic is a hack
          if version_string.include?('>=')
            match = version_string.match(/>=(\s)*([0-9]+\.[0-9]+\.[0-9]+)/)
            min = match[2]
          end

          if version_string.include?('<')
            max = version_string.split('<')[1].strip
          end

          break
        end
      end
    end

    [ min, max ]
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
    if @options[:verbose]
      puts(msg)
      log(msg)
    end
  end

  def info(msg)
    log(msg)
  end

  def warning(msg)
    message = msg.gsub(/WARNING./,'')
    $stderr.puts("WARNING: #{message}")
    log("WARNING: #{message}") if @options[:verbose]
  end

  def log(msg)
    unless @log_file
      @log_file = File.open(@options[:output_file], 'w')
    end
    @log_file.puts(msg) unless msg.nil?
    @log_file.flush
  end

  def parse_command_line(args)

   program = File.basename(__FILE__)
    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{program} [OPTIONS] -p PUPPETFILE"

      opts.on(
        '-d', '--root-dir ROOT_DIR',
        'Root directory in which projects will be checked out.',
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

      opts.on(
        '-p', '--puppetfile PUPPETFILE',
        'Puppetfile containing all components that may be in a SIMP release.',
      ) do |puppetfile|
        @options[:puppetfile] = File.expand_path(puppetfile)
      end

      opts.on(
        '-s', '--[no-]clean-start',
        'Start with a fresh checkout of components (Puppet modules',
        'and assets). Existing component directories will be removed.',
        "Defaults to #{@options[:clean_start]}."
      ) do |clean_start|
        @options[:clean_start] = clean_start
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

      unless @options[:help_requested]
        raise ('Puppetfile containing all components must be specified') if @options[:puppetfile].nil?
      end
    rescue RuntimeError,OptionParser::ParseError => e
      raise "#{e.message}\n#{opt_parser.to_s}"
    end
  ensure
    @log_file.close unless @log_file.nil?
  end

  def report_results(results)
    debug('-'*10)
    columns = [
      'Component',
      'Version',
      'GitHub Ref',
      'SIMP Owned?',
      'CentOS Min Version',
      'CentOS Max Version (Incl)',
      'RHEL Min Version',
      'RHEL Max Version (Incl)',
      'OEL Min Version',
      'OEL Max Version (Incl)',
      'Puppet Min Version',
      'Puppet Max Version (Excl)'
    ]

    info(columns.compact.join(','))
    results.sort
    results.sort_by { |proj_name, proj_info| proj_name }.each do |proj_name, proj_info|
      project_data = [
        proj_name,
        proj_info[:version],
        proj_info[:git_ref],
        proj_info[:simp_owned],
        proj_info[:centos_min_version],
        proj_info[:centos_max_version],
        proj_info[:rhel_min_version],
        proj_info[:rhel_max_version],
        proj_info[:oel_min_version],
        proj_info[:oel_max_version],
        proj_info[:puppet_min_version],
        proj_info[:puppet_max_version]
      ]

      info(project_data.compact.join(','))
    end
  end

  def run(args)
    parse_command_line(args)
    return 0 if @options[:help_requested] # already have logged help

    debug("Running with options = <#{args.join(' ')}>") unless args.empty?
    debug("Internal options=#{@options}")
    puts("START TIME: #{Time.now}")

    check_out_projects if @options[:clean_start]

    results = {}
    get_modules_metadata.each do |name, metadata|
      debug('='*80)
      debug("Processing '#{name}'")
      debug("  Metadata = #{metadata.to_yaml}")
      begin
        proj_info = nil
        git_origin = nil
        git_ref = nil
        Dir.chdir(metadata[:module_path]) do
          git_origin, git_ref = get_git_info
        end

        centos_versions = get_os_versions('CentOS', metadata)
        rhel_versions = get_os_versions('RedHat', metadata)
        oel_versions = get_os_versions('OracleLinux', metadata)
        puppet_versions = get_puppet_versions(metadata)

        entry = {
          :version            => metadata['version'],
          :git_ref            => git_ref,
          :simp_owned         => metadata[:simp_owned],
          :centos_min_version => centos_versions[0],
          :centos_max_version => centos_versions[1],
          :rhel_min_version   => rhel_versions[0],
          :rhel_max_version   => rhel_versions[1],
          :oel_min_version    => oel_versions[0],
          :oel_max_version    => oel_versions[1],
          :puppet_min_version => puppet_versions[0],
          :puppet_max_version => puppet_versions[1],
        }
      rescue => e
        warning("#{name}: #{e}")
        debug(e.backtrace.join("\n"))
        entry = {
          :version         => :unknown,
          :git_ref         => :unknown,
          :simp_owned      => :unknown,
          :centos_versions => [ :unknown ],
          :rhel_versions   => [ :unknown ],
          :oel_versions    => [ :unknown ],
          :puppet_versions => :unknown
        }
      end

      if entry[:simp_owned]
        validate_versions(entry[:centos_min_version],
          entry[:rhel_min_version],
          entry[:oel_min_version],
          "#{name} minimum"
        )

        validate_versions(entry[:centos_max_version],
          entry[:rhel_max_version],
          entry[:oel_max_version],
          "#{name} maximum"
        )
      end

      results[name] = entry
    end

    report_results(results)

    puts("STOP TIME: #{Time.now}")
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

  def validate_versions(centos_ver, rhel_ver, oel_ver, description)
    if [centos_ver, rhel_ver, oel_ver].uniq.size != 1
      warning("#{description} version discrepancy CentOS=#{centos_ver} RHEL=#{rhel_ver} OEL=#{oel_ver}")
    end
  end

end

####################################
if __FILE__ == $0
  reporter = MetadataStatusGenerator.new
  exit reporter.run(ARGV)
end
