#!/usr/bin/env ruby
#

def execute(cmd)
  puts ">> Executing: <#{cmd}>"
  puts `#{cmd} 2>&1`
end

if ARGV.size != 3
  $stderr.puts 'USAGE: <pull URL> <owner> <branch>'
  exit 1
end

pull_url = ARGV[0]
owner = ARGV[1]
branch = ARGV[2]

git_url = pull_url.split('/pull')[0]
execute("git clone #{git_url}.git")

repo_name = git_url.split('/').last
Dir.chdir(repo_name) do
 execute("hub checkout #{pull_url} #{branch}")
 execute("hub remote set-url -p #{owner}")
end
