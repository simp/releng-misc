# sync-travis-env-var.rb


<!-- vim-markdown-toc GFM -->
* [Description](#description)
  * [Why this is useful](#why-this-is-useful)
* [Setup](#setup)
  * [Requirements](#requirements)
* [Usage](#usage)

<!-- vim-markdown-toc -->

## Description

**set_travis_env_vars.rb** sets or deletes an organizations' secrets (e.g.,
release tokens) across multiple Travis CI projects


### Why this is useful

Travis CI's [repository-based environment variables] are useful to store
secrets, but each repository keeps its own settings.  This tool sets multiple
projects' settings at once.

## Setup

### Requirements

* MRI Ruby (tested with MRI Ruby 2.4.5)
* A Travis API token

## Usage

        TRAVIS_TOKEN=<TOKEN> set_travis_env_vars.rb [options] ORG VARIABLE [VALUE]
