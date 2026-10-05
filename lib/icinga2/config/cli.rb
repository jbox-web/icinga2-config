# frozen_string_literal: true

# Before Thor, as fylla asks: requiring it prepends into Thor::Option and
# Thor::Arguments, and an option declared before the require would keep Thor's
# own defaults. It also makes `type: :array` options accept a comma-separated
# form (`--object hosts,services`) on top of Thor's space-separated one.
require 'fylla'
require 'thor'
require 'icinga2/config'

# Prepends the completion generator into Thor and records the executable name
# the generated script drives. Done here rather than in `exe/icinga-config` so
# that `CLI.start` works the same when driven directly, as the specs do.
Fylla.load('icinga-config')

module Icinga2
  module Config
    # Exit codes: 0 no difference, 1 differences detected, 2 usage error. A usage
    # error must never exit 1, so that a cron job cannot mistake a missing
    # snapshot for a configuration change.
    EXIT_DIFF = 1
    EXIT_USAGE = 2

    class CLI < Thor
      include Console
      include Spinner
      include StateReport

      # The shells fylla can generate for, and the method that does it.
      SHELLS = { 'zsh' => :zsh_completion, 'bash' => :bash_completion }.freeze

      def self.exit_on_failure? = true

      desc 'snapshot', 'Fetch the live configuration into snapshots/<timestamp>/'
      def snapshot
        line("Snapshotting #{Client.env('ICINGA_API_HOST')} into #{store.root}", style: :bold)
        result = with_spinner { |report| build_snapshot.take(Time.now.strftime('%Y%m%d-%H%M%S'), &report) }
        settings.objects.each do |object|
          line(format('  %-15<object>s %<count>s objects', object: object, count: result[object]))
        end
        line("Snapshot written to #{result['destination']}", style: :green)
      rescue UsageError, Icinga2::API::Error => e
        abort_usage(actionable(e))
      end

      desc 'list', 'List available snapshots'
      def list
        return line(store.hint, style: :yellow) if store.all.empty?

        store.all.each do |path|
          # What the snapshot carries, not what is configured now: the two differ
          # as soon as `objects:` changes, and the listing must describe the file.
          types = store.types(path)
          line(format('%-18<name>s  %<counts>s', name: File.basename(path), counts: describe(path, types)),
               style: types.empty? ? :yellow : nil)
        end
      end

      desc 'diff [OLD] [NEW]', 'Compare two snapshots (default: the two most recent)'
      # Built when the class loads, so it cannot name the configured list — that
      # is only known once Settings has been discovered. It names the catalogue,
      # which is what `--object` is validated against anyway.
      option :object, type: :array, desc: "Restrict to one of #{TYPES.keys.join(', ')}", banner: 'TYPE'
      option :names_only, type: :boolean, default: false, desc: 'Compare object names only'
      option :all, type: :boolean, default: false, desc: 'List every changed object, not just the first 20'
      def diff(old_ref = 'prev', new_ref = 'latest')
        old_dir = store.resolve(old_ref)
        new_dir = store.resolve(new_ref)
        line("Comparing #{File.basename(old_dir)} -> #{File.basename(new_dir)}", style: :bold)
        line

        comparable = comparable_objects(old_dir, new_dir)
        changed = comparable.count { |object| difference?(object, old_dir, new_dir) }
        changed.zero? ? line('No diff detected', style: :green) : abort_diff
      rescue UsageError => e
        abort_usage(e)
      end

      desc 'completion SHELL', "Print the completion script for #{SHELLS.keys.join(' or ')}"
      def completion(shell)
        generator = SHELLS[shell] or
          raise UsageError, "Cannot generate completion for '#{shell}'. Expected #{SHELLS.keys.join(' or ')}."

        # Straight to stdout, unstyled: the script gets piped into a file or
        # sourced, so anything else on the stream ends up inside a shell function.
        line(Fylla.public_send(generator, self))
      rescue UsageError => e
        abort_usage(e)
      end

      desc 'state HOST [SERVICE]', 'Show the runtime state a snapshot deliberately strips'
      def state(host_name, service_name = nil)
        host = Client.build.hosts.find(host_name) or raise UsageError, "Host '#{host_name}' not found."
        object = service_name ? find_service(host, service_name) : host
        print_state(object.to_hash)
      rescue UsageError, Icinga2::API::Error => e
        abort_usage(actionable(e))
      end

      private

      def settings
        @settings ||= Settings.discover
      end

      # Resolved from the caller's directory, never from where this code happens
      # to be installed: as a gem, `__dir__` would point inside the gem itself.
      def store
        @store ||= Store.new(settings.snapshot_dir)
      end

      # Validated against the catalogue, never against the configured list: a type
      # dropped from `objects:` since a snapshot was taken must stay diffable.
      def requested_objects
        requested = options[:object] or return nil

        unknown = requested - TYPES.keys
        unless unknown.empty?
          raise UsageError,
                "Unknown object type '#{unknown.first}'. Expected #{TYPES.keys.join(', ')}."
        end

        requested
      end

      # The types both snapshots carry. Comparing their intersection is what
      # keeps a snapshot taken with a narrower `objects:` list usable instead of
      # failing the whole diff on the first file the other side does not have.
      #
      # A `--object` naming a type one side lacks stays an error: it was asked
      # for explicitly, so answering "no diff" would be a lie.
      def comparable_objects(old_dir, new_dir)
        shared = store.types(old_dir) & store.types(new_dir)
        requested = requested_objects
        return announce_skipped(shared, store.types(old_dir) | store.types(new_dir)) if requested.nil?

        missing = requested - shared
        raise UsageError, "'#{missing.first}' is missing from one of the two snapshots." unless missing.empty?

        requested
      end

      # A silent skip reads as "those types are identical".
      def announce_skipped(shared, present)
        skipped = present - shared
        unless skipped.empty?
          line("skipped: #{skipped.join(' ')} — carried by only one of the two snapshots", style: :yellow)
        end

        shared
      end

      def find_service(host, name)
        host.services.find(name) or raise UsageError, "Service '#{name}' not found on #{host.name}."
      end

      # A directory holding no `.jsonl` is either an interrupted snapshot or one
      # written by the previous bash tool. Saying so beats an empty line, which
      # would read as a snapshot carrying nothing.
      def describe(path, types)
        return 'unreadable — no object file, or written by the previous bash tool' if types.empty?

        types.map { |object| "#{object}=#{store.read(path, object).size}" }.join(' ')
      end

      # True when this object type differs between the two snapshots.
      def difference?(object, old_dir, new_dir)
        line(object, style: :bold)
        diff = Diff.new(old: store.read(old_dir, object), new: store.read(new_dir, object))
        Reporter.new(diff, names_only: options[:names_only], all: options[:all]).render.difference?
      end

      def abort_diff
        line('Diff detected!!', style: :red)
        exit EXIT_DIFF
      end

      def build_snapshot
        Snapshot.new(store: store, client: Client.build,
                     volatile_vars: settings.volatile_vars, objects: settings.objects)
      end

      # A transport failure is something the caller can fix — a wrong host, a
      # stale password, a master that is down — so it exits 2 like any other
      # usage error, with a message that says which one to look at.
      def actionable(error)
        return error if error.is_a?(UsageError)

        ApiFailure.wrap(error, endpoint: Client.base_url)
      end

      def abort_usage(error)
        warn(paint(error.message, :red))
        exit EXIT_USAGE
      end
    end
  end
end
