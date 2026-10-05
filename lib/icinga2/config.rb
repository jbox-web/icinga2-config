# frozen_string_literal: true

require 'zeitwerk'

# External dependencies, required here because Zeitwerk only autoloads this
# gem's own files. Without this, `Icinga2::API` is defined only once something
# happens to autoload client.rb or api_failure.rb — which made running a single
# spec file fail while the whole suite passed, purely on load order.
require 'icinga2/api'

module Icinga2
  module Config
    # Everything a snapshot *may* capture: the Icinga type behind each name, in
    # the order they are fetched. The names are the plural endpoint names, which
    # is what the files on disk and `--object` have always used; the type catalog
    # in icinga2-api-client only answers to the singular symbol, and rejects the
    # plural locally before sending anything.
    #
    # Configuration types only. `Comment` and `Downtime` are deliberately absent:
    # an operator creates them, and a scheduled rule keeps creating them, so they
    # would move between two snapshots of a configuration nobody touched — the
    # very noise this tool exists to remove.
    TYPES = {
      'hosts' => :host,
      'services' => :service,
      'notifications' => :notification,
      'hostgroups' => :host_group,
      'servicegroups' => :service_group,
      'usergroups' => :user_group,
      'users' => :user,
      'timeperiods' => :time_period,
      'dependencies' => :dependency,
      'scheduleddowntimes' => :scheduled_downtime
    }.freeze

    # What is captured when the fleet configures nothing. Kept to the three types
    # snapshots have always carried, so that extending TYPES never changes what an
    # existing installation writes — `objects:` in .icinga-config.yml is what opts
    # into the rest.
    DEFAULT_OBJECTS = %w[hosts services notifications].freeze

    # Raised for anything the caller can fix: a bad reference, an incomplete
    # snapshot, an unknown object type. The CLI turns it into exit code 2 — never
    # 1, which means "the configuration changed" and must stay unambiguous for a
    # cron job.
    class UsageError < StandardError; end
  end
end

# Set up after the namespace exists, so that a single `module Icinga2` opens this
# file rather than two.
#
# `for_gem_extension`, not `for_gem`: the entry point is lib/icinga2/config.rb,
# so the root directory is lib/icinga2/ and `for_gem` would map config/store.rb
# onto a top-level `Config::Store` instead of `Icinga2::Config::Store` — every
# constant in this gem failed to resolve that way.
#
# Two names the default inflector cannot guess, both acronyms: cli.rb defines
# CLI, and version.rb defines VERSION.
Zeitwerk::Loader.for_gem_extension(Icinga2).tap do |loader|
  loader.inflector.inflect('cli' => 'CLI', 'version' => 'VERSION')
  loader.setup
end
