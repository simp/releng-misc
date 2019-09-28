#!/usr/bin/env ruby

require 'json'
require 'yaml'

options = { 'action' => 'set', 'public' => false, 'noop' => false }
output  = {}

def error_hash(msg, kind='releng_tasks.tasks/task-error', details = {} )
  JSON.pretty_generate( {
    "_error" => {
      "msg"  => msg,
      "kind" => kind,
      "details" => details
    }
  })
end

raw_structured_input = ''
while input = STDIN.gets
  raw_structured_input += input
end

if raw_structured_input.strip.empty?
  puts error_hash( 'No input on STDIN' )
  exit 98
end

begin
  parameters = JSON.parse(raw_structured_input)
  options.merge!(parameters)
rescue JSON::ParserError => e
  puts error_hash( "STDIN contained content, but it was not valid JSON! (#{e})" )
  exit 99
end

warn '===== t parameters', parameters.to_yaml
warn '===== t options', options.to_yaml

script_file = File.join(options['_installdir'],'releng_tasks/files/set_travis_env_vars.rb')
warn "script_file: '#{script_file}' (#{File.exist?(script_file)})"
warn "TASK __FILE__: '#{__FILE__}'  $0: '#{$0}'"

begin
  require script_file
  TravisCIOrgEnvSetter.run(options)
rescue Exception => e
  puts error_hash(
     "An Error (#{e.class}) occurred: ! (#{e.message})",
     e.class,
     {
       'error_message' => e.message,
       'error_class' => e.class,
       'error_backtrace' => e.backtrace,
     }
  )
  exit 99
end
