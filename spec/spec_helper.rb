# frozen_string_literal: true

require 'simplecov'

# Started before the library is required, otherwise every file loaded at require
# time counts as zero-covered. The JSON report is what the CI publishes; the HTML
# one is for reading locally. SimpleCov 1.x ships both formatters itself — the
# separate simplecov-html and simplecov_json_formatter gems the 0.22 setups pull
# in are no longer dependencies.
SimpleCov.start do
  formatter SimpleCov::Formatter::MultiFormatter.new([SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::JSONFormatter])
  skip 'spec/'

  # Without this, a file no spec ever loads is absent from the report entirely
  # rather than shown at 0% — `cli.rb` is only required by `exe/icinga-config`,
  # so a quarter of the gem used to be invisible instead of visibly untested.
  # `cover` replaces the deprecated `track_files`: it pulls in unloaded files on
  # disk and confines the report to the matching set.
  cover 'lib/**/*.rb'

  # `version.rb` cannot be measured, and its 0% would be a permanent false
  # signal: the Gemfile's `gemspec` directive makes Bundler evaluate the gemspec,
  # which `require_relative`s it, before any of this runs. It is exercised — by
  # the gemspec on every build and by version_spec.rb — just never under
  # observation.
  skip 'lib/icinga2/config/version.rb'
end

RSpec.configure do |config|
  config.color = true
  config.fail_fast = false

  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.disable_monkey_patching!
end

require 'icinga2/config'
