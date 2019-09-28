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

require 'net/http'
require 'uri'
require 'json'
require 'openssl'
require 'optparse'
require 'yaml'

# A fit-for-most-purposes, MRI-compatible HTTP/S swiss army knife method
#
# @param [URI]  uri
# @param [Hash] opts options to configure the connection
# @option opts [String] :content_type
# @option opts [String] :body
# @option opts [String] :params
# @option opts [Hash<String,String>] :headers
# @option opts [Boolean] :use_ssl
# @option opts [<OpenSSL::SSL::VERIFY_PEER,OpenSSL::SSL::VERIFY_NONE>]
#   :verify_mode
# @option opts [Boolean] :show_debug_info
# @param [Net::HTTPGenericRequest] http_request_type
#
# @author Name Chris Tessmer <chris.tessmer@onyxpoint.com>
#
def http_request(uri, opts = {}, http_type = nil)
  http_type  ||= opts[:http_request_type] if opts[:http_request_type]
  http_type  ||= Net::HTTP::Post if opts[:body]
  http_type  ||= Net::HTTP::Get
  uri.query    = URI.encode_www_form(opts[:params]) if opts[:params]
  request      = http_type.new(uri)
  request.body = opts[:body] if opts[:body]

  request.content_type = opts.fetch(:content_type, 'application/json')
  opts.fetch(:headers, {}).each { |header, v| request[header] = v }

  http = Net::HTTP.new(uri.hostname, uri.port)
  http.set_debug_output($stdout) if opts[:show_debug_info]
  if opts[:use_ssl] || uri.scheme == 'https'
    http.use_ssl = true
    http.ca_file = opts[:ca_file] if opts.key?(:ca_file)
    http.verify_mode = opts[:verify_mode] || OpenSSL::SSL::VERIFY_PEER
  end

  response = http.request(request)
  unless response.code =~ /^2\d\d/
    msg = "\n\nERROR: Unexpected HTTP response from:" \
          "\n       #{response.uri}\n" \
          "\n       Response code_type: #{response.code_type} " \
          "\n       Response code:      #{response.code} " +
          (opts.fetch(:show_debug_response, false) ?
            "\n       Response body: " \
            "\n         #{JSON.parse(response.body)} \n\n" \
            "\n       Request body: " \
            "\n#{JSON.parse(request.body).to_yaml.split("\n").map { |x| ' ' * 8 + x }.join("\n")} \n\n"
           : '')
    warn response.body
    raise(msg)
  end

  response
end

class TravisCIOrgEnvSetter
  attr_accessor :dry_run, :verbose, :travis_api
  def initialize(travis_token, org, travis_api=nil)
    @org          = org
    @travis_token = travis_token
    @travis_api   = travis_api || 'https://api.travis-ci.com'
    @headers = {
      'Travis-Api-Version' => '3',
      'Authorization' => "token #{@travis_token}"
    }
    @dry_run = false
    @verbose = false
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
    org_repos_data = travis_http("#{@travis_api}/owner/#{@org}/repos")
    org_repos = org_repos_data['repositories']
    org_repos.map { |x| x['name'] }.sort.each do |repo_name|
      puts "== repo '#{@org}/#{repo_name}'"
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

    each_org_repo do |repo|
      data = travis_http("#{@travis_api}/repo/#{repo['id']}/env_vars")
      env_vars = data['env_vars']

      existing_env_vars = env_vars.select { |x| x['name'] == env_var_name }
      if existing_env_vars.empty?
        puts "  == Create env_var '#{env_var_name}'"
        travis_http("#{@travis_api}/repo/#{repo['id']}/env_vars", body: body)
      else
        env_var_id = existing_env_vars.first['id']
        puts "  == Update env_var '#{env_var_name}' (#{env_var_id})"
        travis_http("#{@travis_api}/repo/#{repo['id']}/env_var/#{env_var_id}",
                    http_request_type: Net::HTTP::Patch,
                    body: body)
      end
    end
  end

  def delete_env_var(env_var_name)
    each_org_repo do |repo|
      data = travis_http("#{@travis_api}/repo/#{repo['id']}/env_vars")
      env_vars = data['env_vars']

      existing_env_vars = env_vars.select { |x| x['name'] == env_var_name }
      if existing_env_vars.empty?
        warn "  !! WARNING: env_var '#{env_var_name}' not found"
      else
        env_var_id = existing_env_vars.first['id']
        puts "  == Delete env_var '#{env_var_name}' (#{env_var_id})"
        travis_http("#{@travis_api}/repo/#{repo['id']}/env_var/#{env_var_id}",
                    http_request_type: Net::HTTP::Delete)
      end
    end
  end
end


# Parse command line
options = { 'action' => 'set', 'public' => false, 'noop' => false }

opt_parser = OptionParser.new do |opts|
  opts.banner = '== simp environment new [options]'
  opts.separator <<-HELP_MSG.gsub(/^ {4}/, '')

    #{File.basename($PROGRAM_NAME)}: Set a Travis CI environment variable
    across all of an organization's repositories

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
  opts.on('--delete', 'Delete env variable from all repos') do
    options['action'] = 'delete'
  end
  opts.on('-h', '--help', 'Print this message and exit') do
    puts opts
    exit
  end
  opts.separator ''
end


raw_structured_input = ''
while input = STDIN.gets
  raw_structured_input += input
end

if raw_structured_input.strip.empty?
  opt_parser.parse!
else
  begin
    structured_input = JSON.parse(raw_structured_input)
    options.merge!(structured_input)
  rescue JSON::ParserError => e
    raise "ERROR: STDIN contained content, but it was not valid JSON! (#{e})"
  end
end

puts '===== structured_input', structured_input.to_yaml
puts '===== options', options.to_yaml

options['variable'] ||=  ARGV.shift || raise(ArgumentError,'ERROR: VARIABLE is required')
  puts "DDDDDDDDDDDDDD###############"
case options['action']
when 'set'
  options['value'] ||= ARGV.shift || raise(ArgumentError,'ERROR: a VALUE is required to set an env var')
end
options['travis_token'] ||= ENV['TRAVIS_TOKEN'] || raise('ERROR: env var TRAVIS_TOKEN is not set')
options['org'] ||=  ARGV.shift || raise(ArgumentError, 'ERROR: ORG is required')
travis_ci_org = TravisCIOrgEnvSetter.new(options['travis_token'], options['org'])

case options['action']
when 'set'
  puts "###############"
  travis_ci_org.set_env_var(options['variable'], options['value'], options['public'] || false)
when 'delete'
  travis_ci_org.delete_env_var(options['variable'])
end
