# frozen_string_literal: true

module Icinga2
  module Config
    # Strips the attributes that move on their own, so that two snapshots of an
    # unchanged configuration are byte-identical and a diff only ever shows what a
    # human changed.
    module Attributes
      # Attributes that change on every check execution, or on an operator action
      # that touches no configuration file.
      # Seeded from https://community.icinga.com/t/dump-diffable-configuration-snapshots/5433/2
      VOLATILE = %w[
        last_check_result last_check last_state last_hard_state last_hard_state_change
        previous_state_change next_check next_update severity state state_type check_attempt
        last_notification next_notification last_problem_notification notified_problem_users
        no_more_notifications notification_number
        flapping flapping_current flapping_last_change downtime_depth
        execution_start execution_end schedule_start schedule_end
        problem handled acknowledgement acknowledgement_expiry acknowledgement_last_change
      ].freeze

      # Matched by pattern rather than listed: the members differ between hosts
      # (up/down/unreachable) and services (ok/warning/critical/unknown), and a
      # pattern cannot silently miss one the way a hand-kept list can.
      STATE_FAMILY = /\Alast_state_/

      # Line numbers move whenever an unrelated line is added above the object.
      SOURCE_NOISE = %w[first_line last_line first_column last_column].freeze

      # `volatile_vars` names the `vars.*` entries that are volatile on this
      # particular installation — a Host object copied into every VM service, for
      # instance. The gem cannot guess them, so it ships none: they come from the
      # consumer's configuration file.
      def self.strip(attrs, volatile_vars: [])
        kept = attrs.reject { |key, _| VOLATILE.include?(key) || key.match?(STATE_FAMILY) }

        kept['source_location'] = kept['source_location'].except(*SOURCE_NOISE) if kept['source_location'].is_a?(Hash)
        kept['vars'] = kept['vars'].except(*volatile_vars) if kept['vars'].is_a?(Hash) && !volatile_vars.empty?

        kept
      end
    end
  end
end
