require 'octokit'

class GitHubRepoPuncher
  DEFAULT_OPTS = {
    debug: false,
    vnd_github_accept: 'application/vnd.github.luke-cage-preview+json',
    github_api_token: nil,
    org: 'simp',
    team_perms: {}
  }

  def initialize(opts = {})
    @opts = DEFAULT_OPTS.merge(opts)

    if @opts[:debug]
      stack = Faraday::RackBuilder.new do |builder|
        builder.response :logger
        builder.use Octokit::Response::RaiseError
        builder.adapter Faraday.default_adapter
      end
      Octokit.middleware = stack
    end

    Octokit.auto_paginate = true
    @client = Octokit::Client.new(
      access_token: @opts[:github_api_token],
      connection_options: {
        headers: [@opts[:vnd_github_accept]],
      }
    )
  end

  def punch_repos(org = @opts[:org])
    @repos = @client.org_repos(org)
    @repos.each { |repo| punch_repo(repo) }
  end

  def punch_repo(repo)
    puts "== #{repo.full_name} - #{repo.html_url}/settings"
    unless @opts[:repo_opts]
      puts "@opts has no :repo_opts!"
      require 'pry'; binding.pry
      fail
    end

    # configure merges, disable wikis, etc
    # -------------------------------------
    puts "    - configure merges, disable wikis, etc (#{repo.full_name})"
    begin
      @client.edit_repository(repo.full_name, @opts[:repo_opts].dup)
    rescue Octokit::UnprocessableEntity => e
      warn e
      require 'pry'; binding.pry
    rescue Octokit::Forbidden => e
      warn e
      return if e.message =~ /Repository was archived so is read-only/

      require 'pry'; binding.pry
    end

    # Set up team permissions
    # ------------------------
    puts "    - Set up team permissions (#{repo.full_name})"
    @opts[:team_perms].each do |team_slug, team_permission|
      team_hash = @client.org_teams('simp').select { |x| x[:slug] == team_slug }.first
      team_id   = team_hash[:id]

      @client.add_team_repository(team_id, repo.full_name, permission: team_permission)
    end

    # Protect branches
    # ------------------------
    # Ensures all branches named 'master', 'simp-master', and '5.X' are protected
    # Applies protect_branch_opts to all protected branches
    puts "    - Protect branches and apply protect_branch_opts (#{repo.full_name})"
    branches_to_protect = @client.branches(repo.full_name).select do |x|
      x[:protected] || (x[:name] =~ /^(master|simp-master|5\.X)/)
    end.map { |x| x[:name] }

    branches_to_protect.each do |branch_name|
      opts = @opts[:protect_branch_opts]
      # FIXME: this hack should be an option
      if repo[:name] =~ /\A(pupmod-simp-dummy|gitlab-beaker-cleanup-driver)\Z/
        next
      end

      @client.protect_branch(repo.full_name, branch_name, opts.merge(accept: @opts[:vnd_github_accept]))
    end
    puts "    ++ COMPLETED: set up #{repo.full_name} - #{repo.html_url}/settings"
  end
end

# `luke-cage-preview` is needed for merge strategy and branch protection
# https://docs.github.com/en/rest/reference/repos#pull-request-merge-configuration-settings
opts = {
  github_api_token: ENV['GITHUB_API_TOKEN'] || fail('No env var GITHUB_API_TOKEN'),
  debug: ENV['DEBUG'] == 'yes',
  org: 'simp',
  repo_opts: {
    allow_rebase_merge: true,
    allow_squash_merge: true,
    allow_merge_commit: false,
    has_issues: false,
    has_wiki: false,
    has_projects: false,
    has_downloads: false,
    permissions: { admin: true, push: true, pull: true },
  },
  team_perms: {
    'reviewers' => 'push',
    'external-hooks' => 'maintain',
    'core' => 'admin',
  },
  protect_branch_opts: {
    enforce_admins: false,
    required_status_checks: {
      strict: true,
      contexts: [
        'WIP',
        # 'ci/gitlab/gitlab.com',
        'Travis CI - Pull Request'
      ],
    },
    required_pull_request_reviews: {
      dismiss_stale_reviews: true,
      require_code_owner_reviews: true,
      required_approving_review_count: 1,
    },
    required_linear_history: true,
    allow_force_pushes: false,
    allow_deletions: false,
  }
}
opts[:vnd_github_accept] = ENV['VND_GITHUB_ACCEPT'] if ENV['VND_GITHUB_ACCEPT']
puncher = GitHubRepoPuncher.new(opts)
puncher.punch_repos
