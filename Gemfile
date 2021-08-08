gem_sources = ENV.fetch('GEM_SERVERS','https://rubygems.org').split(/[, ]+/)

gem_sources.each { |gem_source| source gem_source }

gem 'bolt', ENV.fetch('BOLT_VERSION', '~> 3.14')
gem 'pdk', ENV.fetch('PDK_VERSION', '~> 2.0')
gem 'gitlab'
gem 'simp-rake-helpers', ENV['SIMP_RAKE_HELPERS_VERSION'] || ['> 5.11', '< 6']


ENV['BOLT_DISABLE_ANALYTICS'] ||= 'yes'
