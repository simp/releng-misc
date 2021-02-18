# releng-misc

<!-- vim-markdown-toc GFM -->

* [Overview](#overview)
* [Setup](#setup)
  * [Setup Requirements](#setup-requirements)
  * [Beginning with the releng:: Bolt project](#beginning-with-the-releng-bolt-project)
* [Usage](#usage)
* [Contributing](#contributing)

<!-- vim-markdown-toc -->

## Overview

This project collects the various tools (script, config, notes, etc.) we've
been using to assist with RELENG-related activities. The purpose is to
establish **awareness** of these tools, and give everyone a change to
inspect/improve/use them.

**WARNING** Things collected here may be broken, full of bugs, hard to use, and
out of date.  Don't assume that anything here is suitable to use in
production without inspecting and testing it first.


## Setup

### Setup Requirements

* [Puppet Bolt 3.0+][bolt], installed from an [OS package][bolt-install]
  (don't run from a RubyGem or use rvm)
*  GitHub + GitLab API auth tokens with sufficient scope
* Environment variables:
  * **`GITHUB_API_TOKEN`**
  * **`GITLAB_API_PRIVATE_TOKEN`** - usually needs `api read+write` scope for updating mirrors
* The [`octokit`][octokit-rb] & [`gitlab`][gitlab-rb] RubyGems

### Beginning with the releng:: Bolt project

1. If you are using [rvm], you **must disable it** before running bolt (We need
   to use the `puppet-bolt` package's ruby interpreter):

   ```sh
   rvm use system
   ```

2. Install the RubyGem dependencies using Bolt's `gem` command

   On most platforms:

   ```sh
   /opt/puppetlabs/bolt/bin/gem install --user-install -g gem.deps.rb
   ```

   On Windows:

   ```pwsh
   "C:/Program Files/Puppet Labs/Bolt/bin/gem.bat" install --user-install -g gem.deps.rb
   ```

3. Install the Puppet modules

   ```sh
   bolt module install
   ```

## Usage

This repo contains RELENG-related [Puppet Bolt] orchestration (in the
[Boltdir/](Boltdir/) directory). For information on the available tasks and
plans, run:

```sh
bolt plan show [plan_name]

bolt task show [task_name]

```

## Contributing

* If you'd like to contribute something that you've been using, drop it in a
  new folder (preferably with a small `README.md` to let others know what it
  is). Don't let polishing things hold you up from contributing!

[bolt]: https://puppet.com/docs/bolt/latest/bolt.html
[gitlab-rb]: https://rubygems.org/gems/gitlab
[bolt-install]: https://puppet.com/docs/bolt/latest/bolt_installing.html
[inventory file]: https://puppet.com/docs/bolt/latest/inventory_file_v2.html
[inventory reference plugin]: https://puppet.com/docs/bolt/latest/using_plugins.html#reference-plugins
[`local` transport]: https://puppet.com/docs/bolt/latest/bolt_transports_reference.html#local
[octokit-rb]: https://github.com/octokit/octokit.rb
[Puppet Bolt]: https://puppet.com/docs/bolt/latest/bolt.html
[rvm]: https://rvm.io
