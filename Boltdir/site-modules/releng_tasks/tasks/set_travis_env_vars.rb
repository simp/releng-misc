#!/usr/bin/env ruby

require 'json'
require 'yaml'
require 'stringio'

def error_hash(msg, kind='releng_tasks.tasks/task-error', details = {} )
  JSON.pretty_generate( {
    "_error" => {
      "msg"  => msg,
      "kind" => kind,
      "details" => details
    }
  })
end

def read_structured_input
  options = {
    'action' => 'set',
    'public' => false,
    '_noop' => false,
    'logdest' => StringIO.new,
  }
  raw_structured_input = ''
  while input = STDIN.gets
    raw_structured_input += input
  end

  if raw_structured_input.strip.empty?
    puts error_hash( 'No input on STDIN' )
    exit 97
  end

  begin
    parameters = JSON.parse(raw_structured_input)
    options.merge!(parameters)
  rescue JSON::ParserError => e
    puts error_hash( "STDIN contained content, but it was not valid JSON! (#{e})" )
    exit 98
  end
  options
end

def run_wrapped_script(options)
  begin
    require File.join(
      options['_installdir'],
      'releng_tasks/files/set_travis_env_vars.rb'
    )
    TravisCIOrgEnvSetter.run(options.merge({'noop' => options['_noop']}))
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
end

options = read_structured_input
run_wrapped_script(options)


# Return Structured Output
output = {
  'options' => options.select { |k,v| k !~ /\A(_|travis_token|logdest)/ },
  'log' => options['logdest'].string.split("\n"),
}
unless options['public']
  if output['options']['value']
    output['options']['value'] = '[sensitive]'
  end
end

puts JSON.pretty_generate( output )
