# frozen_string_literal: true

require 'spec_helper'
require 'icinga2/config/version'

RSpec.describe Icinga2::Config::VERSION do
  # The gemspec reads STRING, so a component that stops being an integer, or a
  # STRING that stops being built from the three, breaks packaging rather than
  # anything a test would otherwise notice.
  it 'joins the three components into the string the gemspec publishes' do
    expect(described_class::STRING)
      .to eq([described_class::MAJOR, described_class::MINOR, described_class::PATCH].join('.'))
  end

  it 'is made of integers' do
    expect([described_class::MAJOR, described_class::MINOR, described_class::PATCH]).to all(be_an(Integer))
  end
end
