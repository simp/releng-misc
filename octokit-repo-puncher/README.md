# Octokit Repo Puncher


<!-- vim-markdown-toc GFM -->

* [Description](#description)
* [Setup](#setup)
  * [Requirements](#requirements)
  * [Getting started](#getting-started)
* [Usage](#usage)
  * [Basic usage](#basic-usage)
  * [With octokit debugging information](#with-octokit-debugging-information)
  * [Using an alternate `Accept:` header](#using-an-alternate-accept-header)

<!-- vim-markdown-toc -->

## Description

This script configures all GitHub repositories under https://github.com/simp to
use our "baseline" settings.  This includes settings for merges, protected
branches, and team permissions.

(Originally from https://gist.github.com/op-ct/cfb371fc22df981f4550727d487434b4)


## Setup

### Requirements

* MRI Ruby (tested with MRI Ruby 2.5.7)
* A GitHub API token with sufficient privileges (admin) in the environment
  variable `$GITHUB_API_TOKEN`

### Getting started

```sh
bundle
```

## Usage

### Basic usage

```sh
GITHUB_API_TOKEN="$GITHUB_API_TOKEN" \
  bundle exec ruby repo_puncher.rb
```

### With octokit debugging information

```sh
DEBUG=yes \
GITHUB_API_TOKEN="$GITHUB_API_TOKEN" \
  bundle exec ruby repo_puncher.rb
```

### Using an alternate `Accept:` header

The default is  [`application/vnd.github.luke-cage-preview+json`][0]

```sh
VND_GITHUB_ACCEPT=application/vnd.github.luke-cage-preview+json \
GITHUB_API_TOKEN="$GITHUB_API_TOKEN" \
  bundle exec ruby repo_puncher.rb
```


[0]: https://docs.github.com/en/rest/reference/repos#get-branch-protection--code-samples
