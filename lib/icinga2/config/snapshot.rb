# frozen_string_literal: true

require 'json'
require 'fileutils'

module Icinga2
  module Config
    # Fetches the live configuration and writes it as JSON Lines, one object per
    # line, keys sorted, volatile attributes stripped.
    class Snapshot
      attr_reader :store, :client, :volatile_vars, :objects

      # `objects` is the list of types to capture, already validated by
      # Settings#objects. It defaults here too so that a caller building a
      # Snapshot without settings still gets the historical three.
      def initialize(store:, client:, volatile_vars: [], objects: DEFAULT_OBJECTS)
        @store = store
        @client = client
        @volatile_vars = volatile_vars
        @objects = objects
      end

      # Yields each type just before fetching it, so a caller can report progress
      # without this class knowing anything about terminals — the CLI drives its
      # spinner from here.
      def take(timestamp, &progress)
        destination = File.join(store.root, timestamp)
        FileUtils.mkdir_p(destination)

        begin
          objects.to_h do |object|
            progress&.call(object)
            entries = fetch(object)
            if entries.empty?
              raise UsageError,
                    "No #{object} returned by the API — check the credentials and the API user permissions."
            end

            write(destination, object, entries)
            [object, entries.size]
          end.merge('destination' => destination)
        rescue StandardError
          discard(destination)
          raise
        end
      end

      # Goes through the generic collection rather than building the URL by
      # hand: the catalog resolves the endpoint and rejects an unknown type
      # locally, before a request is sent, and the collection flips to POST on
      # its own when the query outgrows the request line.
      #
      # The identity block is what keeps the raw `attrs` hash — string keys, as
      # the rest of this gem reads them. Without it the collection would build
      # Host and Service objects, whose `to_hash` symbolises every key.
      def fetch(object)
        client.objects(TYPES.fetch(object))
              .all { |attrs| attrs }
              .map { |attrs| Attributes.strip(attrs, volatile_vars: volatile_vars) }
              .sort_by { |attrs| attrs[Diff::NAME].to_s }
      end

      private

      # A snapshot that failed before writing anything must not leave an empty
      # directory behind: it would become `latest`, and the next diff would resolve
      # to it. `rmdir` only succeeds on an empty directory, so a snapshot that got
      # some object types through keeps what it managed to fetch.
      def discard(destination)
        Dir.glob(File.join(destination, '.*.part')).each { |partial| File.delete(partial) }
        Dir.rmdir(destination)
      rescue SystemCallError
        nil
      end

      # Written to a partial file first: a snapshot interrupted halfway would
      # otherwise look complete and be compared as if it were.
      def write(destination, object, objects)
        partial = File.join(destination, ".#{object}.#{Store::EXTENSION}.part")
        File.open(partial, 'w') do |file|
          objects.each { |attrs| file.puts(JSON.generate(sort_deep(attrs))) }
        end
        FileUtils.mv(partial, File.join(destination, "#{object}.#{Store::EXTENSION}"))
      end

      # Sorting the keys at every level is what makes two snapshots of an
      # unchanged configuration compare equal line by line.
      def sort_deep(value)
        case value
        when Hash then value.sort.to_h { |key, nested| [key, sort_deep(nested)] }
        when Array then value.map { |nested| sort_deep(nested) }
        else value
        end
      end
    end
  end
end
