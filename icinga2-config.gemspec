# frozen_string_literal: true

require_relative 'lib/icinga2/config/version'

Gem::Specification.new do |s|
  s.name        = 'icinga2-config'
  s.version     = Icinga2::Config::VERSION::STRING
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Nicolas Rodriguez']
  s.email       = ['nico@nicoladmin.fr']
  s.homepage    = 'https://github.com/jbox-web/icinga2-config'
  s.summary     = 'Snapshot, diff and inspect a live Icinga 2 configuration'
  s.description = <<~TEXT
    Fetches the live configuration of an Icinga 2 master through its API and writes
    it as a diffable snapshot, with the attributes that move on their own stripped
    at fetch time. Compares two snapshots structurally, reporting which attribute
    changed on how many objects, and exposes the runtime state a snapshot leaves out.
  TEXT

  s.license  = 'MIT'

  s.metadata = {
    'homepage_uri' => s.homepage,
    'source_code_uri' => s.homepage,
    'bug_tracker_uri' => "#{s.homepage}/issues",
    'rubygems_mfa_required' => 'true'
  }

  s.required_ruby_version = '>= 3.2.0'

  s.files = Dir['lib/**/*.rb', 'exe/*', 'README.md', 'LICENSE']

  s.bindir = 'exe'
  s.executables = ['icinga-config']

  # Generates the shell completion the `completion` command prints.
  s.add_dependency 'fylla'
  s.add_dependency 'hashdiff', '~> 1.2'
  s.add_dependency 'icinga2-api-client'
  # Whirly draws the snapshot spinner; paint is what gives it colour — whirly
  # renders monochrome without it.
  s.add_dependency 'paint', '~> 2.3'
  s.add_dependency 'thor', '~> 1.3'
  s.add_dependency 'whirly', '~> 0.4'
  s.add_dependency 'zeitwerk'
end
