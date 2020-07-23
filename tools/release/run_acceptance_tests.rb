#!/usr/bin/env ruby
#
require 'fileutils'
require 'optparse'

class AcceptanceTestRunner

  DEFAULT_ROOT_DIR         = File.expand_path('.')
#  DEFAULT_PUPPET_VERSION   = '4.10.6'
  DEFAULT_PUPPET_VERSION   = '4.10.9'

  DEFAULT_RUN_ALL_TESTS          = false
  DEFAULT_RUN_CORE_TESTS         = false
  DEFAULT_RUN_MODULE_TESTS       = true
  DEFAULT_RUN_ASSET_TESTS        = false
  DEFAULT_RUN_WITH_FIPS_TESTS    = true
  DEFAULT_RUN_WITHOUT_FIPS_TESTS = true

  DEFAULT_LOG_FILE         = 'acceptance_tests.log'
  DEFAULT_LOG_CONSOLE      = false
  DEFAULT_CLEAN_START      = true
  DEFAULT_DRY_RUN          = false
  DEFAULT_VERBOSE          = false

  # These separators are used by the report generator to parse the log
  COMPONENT_SEPARATOR      = '<'*3 + '#'*80 + '>'*3
  TEST_SEPARATOR           = '^'*80

  def check_out_projects(opts)
    log('Preparing a clean projects checkout')
    # make sure we are starting clean
    Dir.chdir(opts[:root_dir]) do
      # rake deps:clean doesn't exist in versions of simp-core < 6.2.0,
      # so we have to replicate that code here
=begin
FIXME
      r10k_helper = R10KHelper.new('Puppetfile.tracking')

      Array(r10k_helper.modules).each do |mod|
        log("Removing #{mod[:path]}") if (Dir.exist?(mod[:path]) and verbose)
        FileUtils.rm_rf(mod[:path])
      end
=end
      ['adapter', 'environment', 'gpgkeys',  'rsync_data',  'rubygem_simp_cli',  'utils'].each do |asset|
        asset_path = File.join(opts[:root_dir], 'src', 'assets', asset)
        log("Removing #{asset_path}") if (Dir.exist?(asset_path) and opts[:verbose])
        FileUtils.rm_rf(asset_path)
      end

      modules_path = File.join(opts[:root_dir],'src', 'puppet', 'modules')
      log("Removing #{modules_path}") if (Dir.exist?(modules_path) and opts[:verbose])
      FileUtils.rm_rf(modules_path)

      execute("#{opts[:env_str]} bundle update", opts[:verbose])
      execute("#{opts[:env_str]} bundle exec rake deps:checkout", opts[:verbose])
    end
  end

  def load_module_metadata(file_path = '.')
    require 'json'
    JSON.parse(File.read(File.join(file_path, 'metadata.json')))
  end

  def log(msg)
    if @logger
      @logger.puts(msg)
      @logger.flush
    end

    if @log_console or @logger.nil?
      puts(msg)
    end
  end

  def get_acceptance_tests(file_path, env_str)
    # FIXME Can't use tests listed in gitlab-ci.yml as they are incomplete
    #  gitlab_tests = get_acceptance_tests_from_gitlab(file_path, env_str)
    discovered_tests = get_acceptance_tests_from_files(file_path, env_str)
  end

  def get_acceptance_tests_from_gitlab(file_path, env_str)
    require 'yaml'
    yaml_file = File.join(file_path, '.gitlab-ci.yml')
    acceptance_tests = []
    if File.exist?(yaml_file)
      yaml = YAML.load(File.read(File.join(file_path, '.gitlab-ci.yml')))
      acceptance_test_yaml = yaml.keep_if do |key, value|
        value.is_a?(Hash) and
        ((value['stage'] == 'acceptance') or key.include?('accept')) and
        ! value['allow_failure']
      end

      acceptance_test_yaml.each do |test, params|
        env_vars = params['variables'].is_a?(Hash) ? params['variables'] : {}
        #FIXME get env variables straightened out
        #test_env = env_str + env_vars.to_a.map { |pair| pair.join('=') }.join(' ')
        test_env = env_vars.to_a.map { |pair| pair.join('=') }.join(' ')
        acceptance_tests << "#{test_env} #{params['script'][-1]}"
      end
    else
      log(">>> NO .gitlab-ci.yml exists for #{File.basename(file_path)}")
    end

    # We don't support Puppet 5 testing yet
    acceptance_tests.delete_if { |test| test.include?('puppet5') or test.include?('oel_p5') }
    acceptance_tests
  end

  def get_acceptance_tests_from_files(file_path, env_str)
    # some of our modules have skeletal acceptance test directories with no tests
    return [] if Dir.glob(File.join(file_path, 'spec', 'acceptance','**', '*_spec.rb')).empty?

    # use simp-core/src/puppet/modules as the location for modules in fixtures.yml
    acceptance_tests = []
    suites_dir = File.join(file_path, 'spec', 'acceptance','suites')
    module_path = File.dirname(file_path)
    test_env = "#{env_str} SIMP_RSPEC_MODULEPATH=#{module_path}"
    if Dir.exist?(suites_dir)
      Dir.entries(suites_dir).sort.each do |suite|
        next if suite[0] == '.'
        next if Dir.glob(File.join(suites_dir, suite, '*_spec.rb')).empty?

        acceptance_tests << "#{test_env} bundle exec rake beaker:suites[#{suite}]"
        acceptance_tests << "#{test_env} BEAKER_fips=yes bundle exec rake beaker:suites[#{suite}]"
      end
    else
      acceptance_tests << "#{test_env} bundle exec rake acceptance"
      acceptance_tests << "#{test_env} BEAKER_fips=yes bundle exec rake acceptance"
    end
    acceptance_tests
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

  def get_simp_owned_modules(modules_dir, opts)
    simp_modules = {}

    # first determine all SIMP-owned modules and their versions
    modules = Dir.entries(modules_dir).delete_if { |dir| dir[0] == '.' }
    modules.sort.each do |module_name|
      metadata = load_module_metadata(File.join(modules_dir, module_name))
      if metadata['name'].split('-')[0] == 'simp'
        simp_modules[module_name] = metadata['version']
      end
    end

    # if specific components specified, only do the valid puppet modules
    unless opts[:all_components]
      simp_modules.delete_if {|name, ver| ! opts[:components].include?(name) }
    end
    simp_modules
  end

  def execute(command, log_command=true, dry_run = false)
    log("Executing: #{command}") if log_command
    unless dry_run
      log(`#{command} 2>&1 | egrep -v 'warning: already initialized constant|warning: previous definition|internal vendored libraries are Private APIs and can change without warning'`)
    end
  end

  def run_asset_tests(opts)
    fail("Not yet supported")
  end

  def run_puppet_module_tests(opts)
    modules_dir = File.join(opts[:root_dir], 'src', 'puppet', 'modules')

    get_simp_owned_modules(modules_dir, opts).each do |module_name,version|
      module_dir = File.join(modules_dir, module_name)

      Dir.chdir(module_dir) do
        git_origin, git_revision = get_git_info
        module_info = "#{module_name} version=#{version} #{git_origin} ref=#{git_revision}"

        acceptance_tests = get_acceptance_tests(module_dir, opts[:env_str])
        log(COMPONENT_SEPARATOR)
        if acceptance_tests.empty?
          log("No acceptance tests for #{module_info}")
          next
        end

        log("Processing #{module_info}")

        # FIXME
        # temporarily remove travis gems that are problematic for Ruby 2.1.9
        gems = IO.readlines('Gemfile')
        gems.delete_if {|gem| gem.include?('travis') }
        File.open('Gemfile', 'w') { |file| file.puts gems.join("\n") }

        execute("#{opts[:env_str]} bundle update", opts[:verbose], opts[:dry_run])

        acceptance_tests.each do |test|
          log(TEST_SEPARATOR) unless opts[:dry_run]
          # make sure starting with clean, generated fixtures file
          FileUtils.rm_rf(File.join(module_name, 'spec', 'fixtures', 'modules'))
          FileUtils.rm_rf(File.join(module_name, 'spec', 'fixtures', 'simp_rspec'))
          execute(test, true, opts[:dry_run])
        end
      end
    end
  end

  def run_simp_core_tests(opts)
    Dir.chdir(opts[:root_dir]) do
      git_origin, git_revision = get_git_info
      acceptance_tests = get_acceptance_tests(opts[:root_dir], opts[:env_str])

      # Delete tests that don't exercise modules in Puppetfile.tracking
      #FIXME this delete list is fragile
      acceptance_tests.delete_if do |test|
        test.include?('forge_install') or
        test.include?('kubernetes') or
        test.include?('rpm_docker') or
        test.include?('rpm_el6') or
        test.include?('rpm_el7')
      end

      # make sure tar files have already been created
      ['6', '7'].each do |os_version|
        tar_glob = File.join('build', 'distributions','CentOS', os_version,
          'x86_64', 'DVD_Overlay', 'SIMP*.tar.gz')

        if Dir.glob(tar_glob).empty?
          fail("SIMP overlay not found in #{File.dirname(tar_glob)}") unless opts[:dry_run]
        end
      end

      metadata = load_module_metadata(opts[:root_dir])

      log(COMPONENT_SEPARATOR)
      log("Processing #{metadata['name']} version=#{metadata['version']} #{git_origin} ref=#{git_revision}")
      execute("#{opts[:env_str]} bundle update", opts[:verbose], opts[:dry_run])

      acceptance_tests.each do |test|
        log(TEST_SEPARATOR) unless opts[:dry_run]
        execute(test, true, opts[:dry_run])
      end
    end
  end

  def set_up_log(log_file, log_console)
    if File.exist?(log_file)
      timestamp = File.stat(log_file).mtime.strftime("%Y-%m-%dT%H%M%S")
      log_backup = "#{log_file}.#{timestamp}"
      FileUtils.mv(log_file, log_backup)
    end
    @logger = File.open(log_file, 'w')
    @log_console = log_console
  end

  def parse_command_line(args)
    options = {
      :root_dir            => DEFAULT_ROOT_DIR,
      :puppet_version      => DEFAULT_PUPPET_VERSION,
      :all_tests           => DEFAULT_RUN_ALL_TESTS,
      :core_tests          => DEFAULT_RUN_CORE_TESTS,
      :module_tests        => DEFAULT_RUN_MODULE_TESTS,
      :asset_tests         => DEFAULT_RUN_ASSET_TESTS,
      :all_components      => true,
      :components          => [],
      :env                 => [],
      :with_fips_test      => DEFAULT_RUN_WITH_FIPS_TESTS,
      :without_fips_test   => DEFAULT_RUN_WITHOUT_FIPS_TESTS,
      :log_file            => DEFAULT_LOG_FILE,
      :log_console         => DEFAULT_LOG_CONSOLE,
      :clean_start         => DEFAULT_CLEAN_START,
      :dry_run             => DEFAULT_DRY_RUN,
      :verbose             => DEFAULT_VERBOSE,
      :help_requested      => false
    }

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename(__FILE__)} [options]"
      opts.separator ''
#      opts.summary_width = 26
#      opts.summary_indent = '  '

      opts.on(
        '-d', '--root-dir ROOT_DIR',
        'Root directory of simp-core checkout.',
        'Defaults to current directory.'
      ) do |root_dir|
        options[:root_dir] = File.expand_path(root_dir)
      end

      opts.on(
        '-p', '--puppet-version PUPPET_VERSION',
        'Puppet version (x.y.z) to install for the tests.',
        'Currently, only Puppet 4 is supported.',
        "Defaults to '#{DEFAULT_PUPPET_VERSION}'."
      ) do |puppet_version|
        options[:puppet_version] = puppet_version
      end

#NOT READY YET
=begin
      opts.on(
        '-A', '--[no-]all-tests',
        'Run simp-core, Puppet module, and asset acceptance tests.',
        'Overrides --[no-]core-tests, --[no-]module-tests, and --[no-]asset-tests.',
        "Defaults to #{run_state(DEFAULT_RUN_ALL_TESTS)} all test types."
      ) do |all_tests|
        options[:all_tests] = all_tests
      end

=end
      opts.on(
        '-c', '--[no-]core-tests',
        'Run (appropriate subset of) simp-core acceptance tests.',
        "Defaults to #{run_state(DEFAULT_RUN_CORE_TESTS)} simp-core tests."
      ) do |core_tests|
        options[:core_tests] = core_tests
      end

      opts.on(
        '-m', '--[no-]module-tests',
        'Run Puppet module acceptance tests.',
        "Defaults to #{run_state(DEFAULT_RUN_MODULE_TESTS)} Puppet module tests."
      ) do |module_tests|
        options[:module_tests] = module_tests
      end

#NOT READY YET
=begin
      opts.on(
        '-a', '--[no-]asset-tests',
        'Run asset acceptance tests.',
        "Defaults to #{run_state(DEFAULT_RUN_ASSET_TESTS)} asset tests."
      ) do |asset_tests|
        options[:asset_tests] = asset_tests
      end
=end

      opts.on(
        '-C', '--component-list COMP1,COMP2,COMP3',
        Array,
        'Optional list of SIMP-owned Puppet modules/assets to be tested.',
        "Each name should match the component's base directory name in",
        "simp-core/src/*. For example '--component-list adapter,ssh'.",
        'Invalid/inappropriate component names are *ignored*.',
        'By default, the list contains all SIMP-owned components.'
      ) do |components|
        options[:components] = components
        options[:all_components] = false
      end

      opts.on(
        '-e', '--env ENV1,ENV2,ENV3',
        Array,
        'Optional list of of environment variables to be passed to each',
        "test.  For example '--env BEAKER_set_autofs_version=yes'."
      ) do |env|
        options[:env] = env
      end

=begin
FINISH ME
      opts.on(
        '-t', '--test-option OPTION',
        'Refinement on tests to run:',
        " f = 'fips-only', n = 'non-fips-only', b = 'both'",
        "Defaults to '#{DEFAULT_XXXXXXXXXXX}'."
      ) do |test-option|
        options[:test-option] = test-option
      end
=end

      opts.on(
        '-l', '--log-file LOGFILE',
        'Fully qualified path to test output log file.',
        "Defaults to '#{DEFAULT_LOG_FILE}'."
      ) do |log_file|
        options[:log_file] = log_file
      end

      opts.on(
        '-L', '--[no-]log-console',
        'Log to console in addition to the log file.',
        "Defaults to '#{DEFAULT_LOG_CONSOLE}'."
      ) do |log_console|
        options[:log_console] = log_console
      end

      opts.on(
        '-s', '--[no-]clean-start',
        'Start with a fresh checkout of Puppet modules/assets.',
        'Existing module/asset directories will be removed.',
        "Defaults to #{DEFAULT_CLEAN_START}."
      ) do |clean_start|
        options[:clean_start] = clean_start
      end

      opts.on(
        '-D', '--dry-run',
        "Print the test commands, but don't execute them.",
        "Defaults to #{DEFAULT_DRY_RUN}."
      ) do
        options[:dry_run] = true
      end

      opts.on(
        '-v', '--verbose',
        "Print all commands executed. Defaults to #{DEFAULT_VERBOSE}."
      ) do
        options[:verbose] = true
      end

      opts.on( "-h", "--help", "Print this help message") do
        options[:help_requested] = true
        puts opts
      end
    end

    begin
      opt_parser.parse!(args)

      if options[:all_tests]
        options[:core_tests] = true
        options[:module_tests] = true
        options[:asset_tests] = true
      end

      validate_options(options)

      # pre-populate with environment variables required for build/test
      test_env = [
       "SIMP_RAKE_HELPERS_VERSION='~> 5.5'",
       "SIMP_RSPEC_PUPPET_FACTS_VERSION='~>2'",
       "PUPPET_VERSION=#{options[:puppet_version]}"
      ]
      options[:env_str] = (test_env + options[:env]).join(' ')

    rescue RuntimeError,OptionParser::ParseError => e
      raise "#{e.message}\n#{opt_parser.to_s}"
    end

    options
  end

  def run(args)
    args_save = args.dup
    opts = parse_command_line(args)
    return 0 if opts[:help_requested] # already have logged help

    set_up_log(opts[:log_file], opts[:log_console])
    log("Running with options = <#{args_save.join(' ')}>")
    log("Internal opts=#{opts}") if opts[:verbose]
    log("START TIME: #{Time.now}")

    run_simp_core_tests(opts)     if opts[:core_tests]

    check_out_projects(opts)      if opts[:clean_start] and (opts[:module_tests] or opts[:asset_tests])
    run_puppet_module_tests(opts) if opts[:module_tests]
    run_asset_tests(opts)         if opts[:asset_tests]
    log("STOP TIME: #{Time.now}")
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
  ensure
    @logger.close if @logger
  end

  def run_state(running_bool)
    running_bool ? 'running' : 'not running'
  end

  def validate_options(options)
    if options[:puppet_version][0] != '4'
      raise "Only Puppet 4 is supported."
    end

   unless options[:core_tests] or options[:module_tests] or options[:asset_tests]
     raise "No tests specified."
   end

   unless options[:all_components] or !options[:components].empty?
     raise "No Puppet modules/assets have been specified."
   end
  end

end

####################################
if __FILE__ == $0
  runner = AcceptanceTestRunner.new
  exit runner.run(ARGV)
end

