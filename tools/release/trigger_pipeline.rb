#!/usr/bin/env ruby
require 'gitlab'
require 'optparse'

$options = {
  :endpoint           => (ENV['GITLAB_URL'] || 'https://gitlab.com/api/v4'),
  :org                => 'simp',
  :branch             => 'master',
  #TODO make this configurable
  :pipeline_variables => {
    'SIMP_FORCE_RUN_MATRIX' => 'yes',
    'SIMP_MATRIX_LEVEL'     => 2
   }
}

opt_parse = OptionParser.new do |opts|
  program = File.basename(__FILE__)
  opts.banner = [
    "Usage: GITLAB_ACCESS_TOKEN=USER_GITLAB_API_TOKEN #{program} [OPTIONS] project1 [project2 ...]"
  ].join("\n")

  opts.separator("\n")

  opts.on('-o', '--org=val', String,
    'GitLab org to query against.',
    "Defaults to '#{$options[:org]}'") do |o|
    $options[:org] = o
  end

  opts.on('-t', '--token=val', String,
    'GitLab API token. This option is NOT recommended.',
    'Use GITLAB_ACCESS_TOKEN environment variable instead.'
  ) do |t|
    $options[:token] = t
  end

  opts.on('-e', '--endpoint=val', String,
    'GitLab API endpoint',
    "Defaults to #{$options[:endpoint]}") do |e|
    $options[:endpoint] = e
  end

  opts.on('-h', '--help', 'Print this menu') do
    puts opts
    exit
  end
end

opt_parse.parse!

$options[:projects] = ARGV
if $options[:projects].empty?
  fail("No projects specified.\n#{opt_parse.banner}")
end

unless $options[:token]
  if ENV['GITLAB_ACCESS_TOKEN']
    $options[:token] = ENV['GITLAB_ACCESS_TOKEN']
  else
    fail('GITLAB_ACCESS_TOKEN must be set')
  end
end

# connect to gitlab
gitlab_client = Gitlab.client(
  :endpoint      => $options[:endpoint],
  :private_token => $options[:token]
)

exit_status = 0
$options[:projects].each do |project|
  begin
    proj = gitlab_client.project("#{$options[:org]}/#{project}")
    puts "Creating pipeline for #{proj.name}"
    gitlab_client.create_pipeline(proj.id, $options[:branch], $options[:pipeline_variables])
  rescue Exception => e
    # can happen if a GitLab project for the component does not exist
    fail("Unable to create pipeline for '#{:project}':\n  #{e.message}")
    exit_status = -1
  end
end

exit exit_status
