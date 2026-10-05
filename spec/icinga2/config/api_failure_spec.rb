# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Icinga2::Config::ApiFailure do
  let(:endpoint) { 'https://icinga.example.net:5665' }

  def wrap(error)
    described_class.wrap(error, endpoint: endpoint)
  end

  it 'returns a UsageError, so the CLI exits 2 rather than on an undefined status' do
    expect(wrap(Icinga2::API::Error::ConnectionFailed.new('connection refused'))).to be_a(Icinga2::Config::UsageError)
  end

  it 'names what to check when the master cannot be reached' do
    message = wrap(Icinga2::API::Error::ConnectionFailed.new('connection refused')).message

    expect(message).to include(endpoint, 'ICINGA_API_HOST', 'ICINGA_API_PORT')
  end

  it 'points at the credentials on a 4xx, not at the network' do
    message = wrap(Icinga2::API::Error::ClientError.new('401 Unauthorized')).message

    expect(message).to include('ICINGA_API_USER', 'ICINGA_API_PASS')
    expect(message).not_to include('ICINGA_API_HOST')
  end

  # NotFound < ClientError, so a lookup that walks the list in the wrong order
  # would report a missing object as a credentials problem.
  it 'distinguishes a 404 from the credentials error it inherits from' do
    message = wrap(Icinga2::API::Error::NotFound.new('404')).message

    expect(message).not_to include('ICINGA_API_USER')
  end

  it 'blames the master on a 5xx' do
    expect(wrap(Icinga2::API::Error::ServerError.new('500')).message).to include('answered with an error')
  end

  it 'says the request timed out' do
    expect(wrap(Icinga2::API::Error::Timeout.new('execution expired')).message).to include('did not answer in time')
  end

  # Raised locally, before anything is sent, so naming the endpoint would point
  # the reader at a server that was never contacted.
  it 'does not blame the endpoint for an unknown object type' do
    message = wrap(Icinga2::API::Error::UnknownType.new('no such type')).message

    expect(message).to include('object type')
    expect(message).not_to include(endpoint)
  end

  it 'still handles a bare Error it has no specific hint for' do
    expect(wrap(Icinga2::API::Error.new('something else'))).to be_a(Icinga2::Config::UsageError)
  end

  # Without it there is nothing left to diagnose with once the backtrace is gone.
  it 'keeps the original class and message for diagnosis' do
    message = wrap(Icinga2::API::Error::ConnectionFailed.new('Failed to open TCP connection')).message

    expect(message).to include('ConnectionFailed', 'Failed to open TCP connection')
  end
end
