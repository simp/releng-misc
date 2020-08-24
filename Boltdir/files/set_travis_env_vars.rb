#!/usr/bin/env ruby
#
# Set/delete a common env var across all Travis CI repos in an organization
#
# * Requires a Travis CI token set in environment variable `TRAVIS_TOKEN`
# * Uses Travis CI API v3 (https://developer.travis-ci.org)
#
# @author Name Chris Tessmer <chris.tessmer@onyxpoint.com>
# @license https://apache.org/licenses/LICENSE-2.0
#
#   Copyright 2019 Chris Tessmer <chris.tessmer@onyxpoint.com>
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

require 'json'
require 'optparse'
require 'yaml'
require 'logger'

require_relative 'http_request'

class TravisCIOrgEnvSetter
  attr_accessor :noop, :verbose, :travis_api
  def initialize(travis_token, org, logdest = STDERR, noop = false, repo_filter = nil, travis_api = nil)
    @org          = org
    @travis_token = travis_token
    @travis_api   = travis_api || 'https://api.travis-ci.com'
    @headers = {
      'Travis-Api-Version' => '3',
      'Authorization' => "token #{@travis_token}"
    }
    @noop = noop
    @repo_filter = repo_filter
    @logger = Logger.new(logdest)
  end

  def travis_http(api_url, opts = {})
    opts[:headers] ||= {}
    opts[:headers].merge!(
      'Travis-Api-Version' => '3',
      'Authorization' => "token #{@travis_token}"
    )
    response = http_request(URI.parse(api_url), opts)
    JSON.parse(response.body) if response.body
  end

  def each_org_repo
    org_repos = []

    limit = 100
    offset = 0
    loop do
      org_repos_data = travis_http("#{@travis_api}/owner/#{@org}/repos?offset=#{offset}&limit=#{limit}")
      org_repos += org_repos_data['repositories']
      @logger.info "-- found #{org_repos.size}/#{org_repos_data['@pagination']['count']} total org repos from API"
      break if org_repos_data['@pagination']['is_last']

      offset = org_repos_data['@pagination']['next']['offset']
    end

    sorted_repo_names = org_repos.map { |x| x['name'] }.sort
    if @repo_filter
      sorted_repo_names.select! { |repo_name| repo_name =~ /#{@repo_filter}/ }
      @logger.info "-- after filtering: #{sorted_repo_names.size} repos (org total: #{org_repos.size})"
    end

    sorted_repo_names.each do |repo_name|
      @logger.info "== repo '#{@org}/#{repo_name}'"
      repo = org_repos.select { |x| x['name'] == repo_name }.first
      yield repo
    end
  end

  def set_env_var(env_var_name, env_var_value, env_var_public)
    body = {
      'env_var.name' => env_var_name,
      'env_var.value' => env_var_value,
      'env_var.public' => env_var_public
    }.to_json

    repos = []
    each_org_repo do |repo|
      data = travis_http("#{@travis_api}/repo/#{repo['id']}/env_vars")
      env_vars = data['env_vars']
      repos << repo

      existing_env_vars = env_vars.select { |x| x['name'] == env_var_name }
      if existing_env_vars.empty?
        @logger.info "  ++ Create env_var '#{env_var_name}'"
        if @noop
          @logger.info '  -- NOOP: (skipping action)'
          next
        end
        travis_http("#{@travis_api}/repo/#{repo['id']}/env_vars", body: body)
      else
        env_var_id = existing_env_vars.first['id']
        @logger.info "  ^^ Update env_var '#{env_var_name}'"
        @logger.info "     [env_var id: #{env_var_id}]"
        if @noop
          @logger.info '  -- NOOP: (skipping action)'
          next
        end
        travis_http("#{@travis_api}/repo/#{repo['id']}/env_var/#{env_var_id}",
                    http_request_type: Net::HTTP::Patch,
                    body: body)
      end
    end
    @logger.info "  ==== REPOS: (#{repos.size})"
  end

  def list_env_vars
    results = {}
    each_org_repo do |repo|
      data = travis_http("#{@travis_api}/repo/#{repo['id']}/env_vars")
      env_vars = data['env_vars']
      results[repo['name']] = Hash[env_vars.map{|x| [x['name'],x['value']]}]
    end
    results
  end

  def delete_env_var(env_var_name)
    each_org_repo do |repo|
      data = travis_http("#{@travis_api}/repo/#{repo['id']}/env_vars")
      env_vars = data['env_vars']

      existing_env_vars = env_vars.select { |x| x['name'] == env_var_name }
      if existing_env_vars.empty?
        @logger.warn "  !! WARNING: env_var '#{env_var_name}' not found"
      else
        env_var_id = existing_env_vars.first['id']
        @logger.info "  == Delete env_var '#{env_var_name}' (#{env_var_id})"
        if @noop
          @logger.info '  -- NOOP: (skipping action)'
          next
        end
        travis_http("#{@travis_api}/repo/#{repo['id']}/env_var/#{env_var_id}",
                    http_request_type: Net::HTTP::Delete)
      end
    end
  end

  def TravisCIOrgEnvSetter.run(options)
    case options['action']
    when 'set'
      options['variable'] || raise(ArgumentError, 'VARIABLE is required')
      options['value'] || raise(ArgumentError, 'A VALUE is required to set an env var')
    when 'delete'
      options['variable'] || raise(ArgumentError, 'VARIABLE is required')
    end
    options['travis_token'] || raise('TRAVIS_TOKEN is not set')
    options['org']          || raise(ArgumentError, 'ORG is required')

    travis_ci_org = TravisCIOrgEnvSetter.new(
      options['travis_token'],
      options['org'],
      options['logdest'] || nil,
      options['noop'] || false,
      options['repo_filter'] || nil,
      options['travis_api'] || nil
    )

    case options['action']
    when 'list'
      travis_ci_org.list_env_vars
    when 'set'
      travis_ci_org.set_env_var(
        options['variable'],
        options['value'],
        options['public'] || false
      )
    when 'delete'
      travis_ci_org.delete_env_var(options['variable'])
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  # Parse command line
  options = { 'action' => 'set', 'public' => false, 'noop' => false }

  perma_opts = ''
  opt_parser = OptionParser.new do |opts|
    opts.banner = "== #{File.basename($PROGRAM_NAME)} [options]"
    opts.separator <<-HELP_MSG.gsub(/^ {4}/, '')

      Set a Travis CI environment variable across all of an organization's
      repositories

      Usage:

        TRAVIS_TOKEN=<TOKEN> #{File.basename($PROGRAM_NAME)} [options] ORG VARIABLE [VALUE]

      Note:

        The environment variable TRAVIS_TOKEN must contain your Travis CI token
    HELP_MSG

    opts.separator ''
    opts.on(
      '--[no-]public',
      'Make env variable publicly visible (default: no)'
    ) do |arg|
      options['public'] = arg
    end
    opts.on(
      '--[no-]noop',
      'Print actions but do not change anything (default: no)'
    ) do |arg|
      options['public'] = arg
    end
    opts.on('--list', 'List env variables from all repos') do
      options['action'] = 'list'
    end
    opts.on('--delete', 'Delete env variable from all repos') do
      options['action'] = 'delete'
    end
    opts.on('--travis-api', 'Travis API URI (default: https://api.travis-ci.com)') do |arg|
      options['travis_api'] = arg
    end
    opts.on('-h', '--help', 'Print this message and exit') do
      puts opts
      exit
    end
    perma_opts = opts
    opts.separator ''
  end

  opt_parser.parse!

  options['org'] ||=  ARGV.shift
  options['variable'] ||= ARGV.shift
  case options['action']
  when 'set'
    options['value'] ||= ARGV.shift
  end
  options['travis_token'] ||= ENV['TRAVIS_TOKEN']

  begin
    result = TravisCIOrgEnvSetter.run(options)
    puts result.to_yaml if options['action'] == 'list'
  rescue ArgumentError => e
    warn '', '-' * 80, "ERROR: #{e}", '-' * 80, ''
    warn 'options:', options.to_yaml
    warn perma_opts
    exit 1
  end
end
