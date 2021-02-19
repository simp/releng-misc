#!/opt/puppetlabs/bolt/bin/ruby
# frozen_string_literal: true

require_relative ENV['TASK_HELPER_RB'] || '../../ruby_task_helper/files/task_helper.rb'

require 'pathname'
require 'json'
require 'yaml'

# Return depaginated results for a GitLab API request
class GitlabApiRequest < TaskHelper
  def depaginate(paginated_things, max_pages=100)
    things = paginated_things
    pages_seen = 0
    while paginated_things.has_next_page? && pages_seen <= max_pages
      paginated_things = paginated_things.next_page
      pages_seen += 1
      things += paginated_things
    end
    things
  end

  def task(name: nil, **kwargs) # rubocop:disable Lint/UnusedMethodArgument
    Dir["#{kwargs[:extra_gem_path]}/gems/*/lib"].each { |path| $LOAD_PATH << path } # for gitlab

    group               = kwargs[:group]
    gitlab_api_token    = kwargs[:gitlab_api_token]
    gitlab_api_endpoint = kwargs[:gitlab_api_endpoint]
    path                = kwargs[:path].sub(gitlab_api_endpoint,'')
    max_pages           = kwargs[:max_pages]
    extra_gem_path      = kwargs[:extra_gem_path]

    require 'gitlab'
    @client = Gitlab.client(
      endpoint: gitlab_api_endpoint,
      private_token: gitlab_api_token,
    )
    result = depaginate( @client.send(:get, path), max_pages)

    { body: result.map(&:to_hash) }
  end
end

GitlabApiRequest.run if $PROGRAM_NAME == __FILE__
