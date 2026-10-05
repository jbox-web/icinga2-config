# frozen_string_literal: true

require 'icinga2/api'

module Icinga2
  module Config
    # Builds the API client from the environment, with the same variable names and
    # the same defaults as the bash tool it replaces. Credentials reach the client
    # through the environment only: never through ARGV, where `ps` would expose
    # them to every local account.
    module Client
      DEFAULTS = {
        'ICINGA_API_HOST' => 'icinga.example.net',
        'ICINGA_API_PORT' => '5665',
        'ICINGA_API_USER' => 'root',
        'ICINGA_API_PASS' => 'pass',
        'ICINGA_API_SCHEME' => 'https',
        'ICINGA_API_INSECURE' => '1',
        'ICINGA_API_CACERT' => ''
      }.freeze

      def self.env(key)
        value = ENV.fetch(key, nil)
        value.nil? || value.empty? ? DEFAULTS.fetch(key) : value
      end

      def self.base_url
        format('%<scheme>s://%<host>s:%<port>s',
               scheme: env('ICINGA_API_SCHEME'), host: env('ICINGA_API_HOST'), port: env('ICINGA_API_PORT'))
      end

      def self.build
        Icinga2::API::Client.new(base_url, version: 'v1', username: env('ICINGA_API_USER'),
                                           password: env('ICINGA_API_PASS'), ssl_options: ssl_options)
      end

      # The master presents a certificate signed by the Icinga internal CA, which
      # the system trust store does not know about. Pinning the CA is preferred;
      # skipping verification is the documented fallback.
      def self.ssl_options
        cacert = env('ICINGA_API_CACERT')
        return { ca_file: cacert } unless cacert.empty?

        env('ICINGA_API_INSECURE') == '1' ? { verify: false } : {}
      end
    end
  end
end
