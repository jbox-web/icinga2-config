# frozen_string_literal: true

require 'yaml'

module Icinga2
  module Config
    # What belongs to the fleet rather than to the tool: where snapshots live, and
    # which `vars.*` entries are volatile on this particular installation. The gem
    # ships no fleet-specific default — `see_esx_host` means nothing outside the
    # installation that sets it.
    #
    # Precedence: environment, then the file, then a generic default.
    class Settings
      FILENAME = '.icinga-config.yml'
      DEFAULT_SNAPSHOT_DIR = 'snapshots'

      attr_reader :root

      # Walks up from `start` so that the tool behaves the same from a repository
      # subdirectory as from its root.
      def self.discover(start = Dir.pwd, env: ENV)
        directory = File.expand_path(start)

        loop do
          path = File.join(directory, FILENAME)
          return new(load_file(path), root: directory, env: env) if File.exist?(path)

          parent = File.dirname(directory)
          break if parent == directory

          directory = parent
        end

        new({}, root: File.expand_path(start), env: env)
      end

      def self.load_file(path)
        data = YAML.safe_load_file(path)
        return {} if data.nil?
        raise UsageError, "#{path} must contain a mapping, got #{data.class}." unless data.is_a?(Hash)

        data
      end

      def initialize(data = {}, root: Dir.pwd, env: ENV)
        @data = data
        @root = root
        @env = env
      end

      def snapshot_dir
        from_env = @env['ICINGA_SNAPSHOT_DIR']
        return from_env unless from_env.nil? || from_env.empty?

        expand(@data.fetch('snapshot_dir', DEFAULT_SNAPSHOT_DIR))
      end

      # Extra `vars.*` keys to strip, on top of the attributes every Icinga
      # installation has.
      def volatile_vars
        Array(@data['volatile_vars']).map(&:to_s)
      end

      # Which object types a snapshot captures. Validated here rather than at
      # fetch time: the type catalog would reject an unknown one too, but only
      # after the snapshot directory had been created.
      def objects
        return DEFAULT_OBJECTS.dup unless @data.key?('objects')

        configured = @data['objects']
        unless configured.is_a?(Array)
          raise UsageError, "#{FILENAME}: `objects` must be a list, got #{configured.class}."
        end

        names = configured.map(&:to_s)
        raise UsageError, "#{FILENAME}: `objects` is empty — a snapshot needs at least one type." if names.empty?

        reject_uncapturable(names)
        names
      end

      private

      def reject_uncapturable(names)
        unknown = names - TYPES.keys
        return if unknown.empty?

        raise UsageError,
              "#{FILENAME}: cannot capture '#{unknown.first}'. Expected one of #{TYPES.keys.join(', ')}."
      end

      def expand(path)
        File.absolute_path?(path) ? path : File.join(root, path)
      end
    end
  end
end
