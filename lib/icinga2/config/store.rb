# frozen_string_literal: true

require 'json'

module Icinga2
  module Config
    # The snapshot directory: lists what is there, resolves a reference to a path,
    # and reads an object file back.
    class Store
      EXTENSION = 'jsonl'
      # What the bash tool wrote. Detected on purpose, so that an old snapshot
      # produces an explanation instead of a JSON parse error.
      LEGACY_EXTENSION = 'json'

      attr_reader :root

      def initialize(root)
        @root = root
      end

      # Timestamped names make a lexicographic sort chronological.
      def all
        return [] unless Dir.exist?(root)

        Dir.children(root).map { |name| File.join(root, name) }.select { |path| Dir.exist?(path) }.sort
      end

      def names
        all.map { |path| File.basename(path) }
      end

      def resolve(reference)
        case reference
        when 'latest' then all.last || (raise UsageError,
                                              "No snapshot in #{root} — run `icinga-config snapshot` first.")
        when 'prev' then all[-2] || (raise UsageError, "Need at least two snapshots. #{hint}")
        else resolve_path(reference)
        end
      end

      # The object types this snapshot actually carries. Two snapshots taken with
      # different `objects:` lists are compared on the intersection of these, so
      # widening the list does not make every earlier snapshot uncomparable.
      #
      # Only `.jsonl` counts: a `.json` is the previous bash tool's output, which
      # #read refuses, and it must not pass for a comparable type here either.
      def types(directory)
        Dir.glob(File.join(directory, "*.#{EXTENSION}")).map { |path| File.basename(path, ".#{EXTENSION}") }.sort
      end

      def read(directory, object)
        path = File.join(directory, "#{object}.#{EXTENSION}")
        return parse(path) if File.exist?(path)

        if File.exist?(File.join(directory, "#{object}.#{LEGACY_EXTENSION}"))
          raise UsageError,
                "#{File.basename(directory)} was written by the previous bash tool and cannot be read: " \
                'take a fresh snapshot to compare against.'
        end

        raise UsageError, "Missing #{object}.#{EXTENSION} in #{directory} — that snapshot is incomplete."
      end

      def hint
        return "No snapshot in #{root} — run `icinga-config snapshot` first." if names.empty?

        "Available snapshots: #{names.join(' ')}"
      end

      private

      def resolve_path(reference)
        return reference if Dir.exist?(reference)

        candidate = File.join(root, reference)
        return candidate if Dir.exist?(candidate)

        raise UsageError, "Cannot resolve snapshot '#{reference}'. #{hint}"
      end

      def parse(path)
        File.readlines(path, chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
      end
    end
  end
end
