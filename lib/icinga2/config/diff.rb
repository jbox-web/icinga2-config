# frozen_string_literal: true

require 'hashdiff'

module Icinga2
  module Config
    # Compares two sets of Icinga objects. Membership is compared by name, and the
    # objects present on both sides are compared attribute by attribute, so the
    # output can say "`period` changed on 128 objects" rather than showing 128
    # anonymous hunks.
    class Diff
      NAME = '__name'

      def initialize(old:, new:)
        @old = index(old)
        @new = index(new)
      end

      def added
        (@new.keys - @old.keys).sort
      end

      def removed
        (@old.keys - @new.keys).sort
      end

      # { object name => [{ op:, path:, old:, new: }, ...] }, only for objects
      # present on both sides — the others are already reported as added/removed.
      def changed
        @changed ||= (@old.keys & @new.keys).sort.each_with_object({}) do |name, result|
          changes = Hashdiff.diff(@old[name], @new[name]).map { |op, path, left, right| change(op, path, left, right) }
          result[name] = changes unless changes.empty?
        end
      end

      # [[attribute path, number of objects it changed on], ...], most frequent
      # first, ties broken by path so two runs order alike.
      def summary
        counts = Hash.new(0)
        changed.each_value { |changes| changes.each { |change| counts[change[:path]] += 1 } }
        counts.sort_by { |path, count| [-count, path] }
      end

      def any?
        !added.empty? || !removed.empty? || !changed.empty?
      end

      private

      def index(objects)
        objects.to_h { |object| [object[NAME], object] }
      end

      # Hashdiff yields ['~', path, before, after] for a change, and ['+', path,
      # value] / ['-', path, value] for an addition or a removal, where the third
      # element is the value and there is no fourth.
      def change(operator, path, left, right)
        case operator
        when '+' then { op: '+', path: path, old: nil, new: left }
        when '-' then { op: '-', path: path, old: left, new: nil }
        else { op: '~', path: path, old: left, new: right }
        end
      end
    end
  end
end
