# frozen_string_literal: true

module Icinga2
  module Config
    # Renders the runtime state of one host or service — what a snapshot strips
    # on purpose, and what the `state` command exists to show.
    #
    # Symmetric to Reporter, which renders a diff: this one renders a live
    # object, straight from the attribute hash the API returned.
    module StateReport
      include Console

      STATES = { 0 => 'OK', 1 => 'WARNING', 2 => 'CRITICAL', 3 => 'UNKNOWN' }.freeze

      # `attrs` comes from Resource#to_hash, so its own keys are symbols while
      # the nested check result keeps the strings the API sent.
      def print_state(attrs)
        state = attrs[:state].to_i
        result = attrs[:last_check_result] || {}
        line(attrs[:__name].to_s, style: :bold)
        line("  state    : #{state} — #{STATES.fetch(state, '?')} (#{attrs[:state_type] == 1 ? 'hard' : 'soft'})")
        line("  attempts : #{attrs[:check_attempt]}/#{attrs[:max_check_attempts]}")
        line("  since    : #{Time.at(attrs[:last_state_change].to_f)}") if attrs[:last_state_change]
        line("  output   : #{result['output']}")
        line("  command  : #{Array(result['command']).join(' ')}")
      end
    end
  end
end
