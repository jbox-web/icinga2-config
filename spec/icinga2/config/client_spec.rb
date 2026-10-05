# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Icinga2::Config::Client do
  # Every example starts from an environment with no ICINGA_API_* set, so a
  # variable exported in the developer's shell cannot decide the outcome.
  around do |example|
    saved = ENV.select { |key, _| key.start_with?('ICINGA_API_') }
    saved.each_key { |key| ENV.delete(key) }
    example.run
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  describe '.env' do
    it 'returns the value when the variable is set' do
      ENV['ICINGA_API_HOST'] = 'master.example.org'

      expect(described_class.env('ICINGA_API_HOST')).to eq('master.example.org')
    end

    it 'falls back to the default when the variable is unset' do
      expect(described_class.env('ICINGA_API_PORT')).to eq('5665')
    end

    # An exported-but-empty variable is the common shape of an unset one in a
    # sourced env file; treating it as a value would build `https://:5665`.
    it 'falls back to the default when the variable is set but empty' do
      ENV['ICINGA_API_HOST'] = ''

      expect(described_class.env('ICINGA_API_HOST')).to eq('icinga.example.net')
    end

    it 'raises on a key it has no default for, rather than returning nil' do
      expect { described_class.env('ICINGA_API_NONSENSE') }.to raise_error(KeyError)
    end
  end

  describe '.base_url' do
    it 'composes scheme, host and port' do
      ENV['ICINGA_API_SCHEME'] = 'http'
      ENV['ICINGA_API_HOST'] = 'master.example.org'
      ENV['ICINGA_API_PORT'] = '5666'

      expect(described_class.base_url).to eq('http://master.example.org:5666')
    end

    it 'composes from the defaults when nothing is set' do
      expect(described_class.base_url).to eq('https://icinga.example.net:5665')
    end
  end

  describe '.ssl_options' do
    it 'pins the CA bundle when one is given, in preference to skipping verification' do
      ENV['ICINGA_API_CACERT'] = '/etc/icinga2/ca.crt'
      ENV['ICINGA_API_INSECURE'] = '1'

      expect(described_class.ssl_options).to eq(ca_file: '/etc/icinga2/ca.crt')
    end

    it 'skips verification when no CA is given and INSECURE is 1' do
      ENV['ICINGA_API_INSECURE'] = '1'

      expect(described_class.ssl_options).to eq(verify: false)
    end

    # Anything other than the exact string "1" leaves verification on: a stray
    # INSECURE=0 or INSECURE=false must not silently disable TLS checking.
    it 'verifies normally when INSECURE is anything but 1' do
      ENV['ICINGA_API_INSECURE'] = '0'

      expect(described_class.ssl_options).to eq({})
    end
  end

  describe '.build' do
    it 'hands the credentials to the client rather than putting them on a command line' do
      ENV['ICINGA_API_USER'] = 'snapshot'
      ENV['ICINGA_API_PASS'] = 'not-a-real-password'
      allow(Icinga2::API::Client).to receive(:new)

      described_class.build

      expect(Icinga2::API::Client).to have_received(:new).with(
        'https://icinga.example.net:5665',
        version: 'v1', username: 'snapshot', password: 'not-a-real-password', ssl_options: { verify: false }
      )
    end
  end
end
