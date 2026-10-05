# frozen_string_literal: true

require 'icinga2/api'

module Icinga2
  module Config
    # Translates the transport errors icinga2-api-client raises into a
    # UsageError, so a master that is down or a password that is wrong exits 2
    # with something the caller can act on, instead of a Ruby backtrace and a
    # status that is neither 0, 1 nor 2.
    module ApiFailure
      # Ordered most specific first and walked in order, never keyed by class:
      # NotFound < ClientError, so a Hash lookup would miss the subclass and the
      # reverse order would report a missing object as a credentials problem.
      # The last entry is the catch-all, and matches because everything here
      # descends from Icinga2::API::Error.
      HINTS = [
        [Icinga2::API::Error::ConnectionFailed,
         'Cannot reach the Icinga 2 API at %<endpoint>s. ' \
         'Check ICINGA_API_HOST and ICINGA_API_PORT, and that the master is running.'],
        [Icinga2::API::Error::Timeout,
         'The Icinga 2 API at %<endpoint>s did not answer in time.'],
        [Icinga2::API::Error::NotFound,
         'The Icinga 2 API at %<endpoint>s has no such object or endpoint.'],
        [Icinga2::API::Error::ClientError,
         'The Icinga 2 API at %<endpoint>s rejected the request. ' \
         'Check ICINGA_API_USER, ICINGA_API_PASS and the API user permissions.'],
        [Icinga2::API::Error::ServerError,
         'The Icinga 2 master at %<endpoint>s answered with an error.'],
        # Raised locally, before anything is sent: naming the endpoint would
        # point at a server that was never contacted.
        [Icinga2::API::Error::UnknownType,
         'This build of icinga2-api-client does not carry that object type.'],
        [Icinga2::API::Error,
         'The Icinga 2 API at %<endpoint>s failed.']
      ].freeze

      # The original class and message are appended rather than dropped: once
      # the backtrace is gone they are all that is left to diagnose with. Safe to
      # print — the credentials travel in a header, never in the URL these
      # messages quote.
      def self.wrap(error, endpoint:)
        _, hint = HINTS.find { |klass, _| error.is_a?(klass) }

        UsageError.new("#{format(hint, endpoint: endpoint)} (#{short_name(error)}: #{error.message})")
      end

      def self.short_name(error)
        error.class.name.split('::').last
      end
      private_class_method :short_name
    end
  end
end
