# frozen_string_literal: true

module Icinga2
  module Config
    # Renders a Diff. Membership first, then the per-attribute summary — which is
    # what tells "`period` changed on 128 objects" instead of leaving the reader to
    # count hunks — then the changed objects themselves, capped unless asked
    # otherwise. The cap is always announced: a silent truncation reads as "that
    # was everything".
    class Reporter
      include Console

      DETAIL_LIMIT = 20

      def initialize(diff, names_only: false, all: false)
        @diff = diff
        @names_only = names_only
        @all = all
      end

      # Prints the report. Whether it found something is asked separately, through
      # `difference?`, so the caller decides the exit code.
      def render
        membership
        changes unless @names_only

        line('  no change', style: :green) unless difference?
        line
        self
      end

      def difference?
        return !(@diff.added.empty? && @diff.removed.empty?) if @names_only

        @diff.any?
      end

      private

      def membership
        unless @diff.added.empty?
          line("  + #{@diff.added.size} added", style: :green)
          @diff.added.each { |name| line("      + #{name}", style: :green) }
        end
        return if @diff.removed.empty?

        line("  - #{@diff.removed.size} removed", style: :red)
        @diff.removed.each { |name| line("      - #{name}", style: :red) }
      end

      def changes
        return if @diff.changed.empty?

        line("  ~ #{@diff.changed.size} changed", style: :yellow)
        @diff.summary.each do |path, count|
          line(format('      %-40<path>s %<count>d objects', path: path, count: count))
        end
        detail
      end

      def detail
        shown = @all ? @diff.changed.to_a : @diff.changed.first(DETAIL_LIMIT)
        shown.each { |name, changes| object(name, changes) }
        hidden = @diff.changed.size - shown.size
        return if hidden.zero?

        line("      … and #{hidden} more changed objects, use --all to list them", style: :yellow)
      end

      def object(name, changes)
        line("    #{name}")
        changes.each do |change|
          line(format('      %<op>s %<path>s: %<old>s -> %<new>s',
                      op: change[:op], path: change[:path], old: change[:old].inspect, new: change[:new].inspect))
        end
      end
    end
  end
end
