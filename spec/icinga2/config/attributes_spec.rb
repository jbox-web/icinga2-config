# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Icinga2::Config::Attributes do
  describe '.strip' do
    it 'keeps the attributes that describe the configuration' do
      attrs = { '__name' => 'web01!ssh', 'check_command' => 'ssh', 'vars' => { 'port' => 22 } }

      expect(described_class.strip(attrs)).to eq(attrs)
    end

    it 'removes the check result, which changes on every execution' do
      attrs = { '__name' => 'web01!ssh', 'last_check_result' => { 'output' => 'OK' }, 'last_check' => 1.0 }

      expect(described_class.strip(attrs)).to eq('__name' => 'web01!ssh')
    end

    it 'removes the whole last_state_ family, whose members differ between hosts and services' do
      attrs = {
        '__name' => 'web01',
        'last_state_up' => 1.0,
        'last_state_down' => 0.0,
        'last_state_ok' => 1.0,
        'last_state_unreachable' => 0.0
      }

      expect(described_class.strip(attrs)).to eq('__name' => 'web01')
    end

    it 'removes the operator state, which a human acknowledgement changes without touching the config' do
      attrs = { '__name' => 'web01', 'acknowledgement' => 1, 'acknowledgement_last_change' => 2.0,
                'problem' => true, 'handled' => true }

      expect(described_class.strip(attrs)).to eq('__name' => 'web01')
    end

    it 'keeps the source location but drops the line and column numbers' do
      attrs = {
        '__name' => 'web01',
        'source_location' => {
          'path' => '/etc/icinga2/zones.d/jaguar/web01.conf',
          'first_line' => 1, 'last_line' => 12, 'first_column' => 0, 'last_column' => 1
        }
      }

      expect(described_class.strip(attrs)).to eq(
        '__name' => 'web01',
        'source_location' => { 'path' => '/etc/icinga2/zones.d/jaguar/web01.conf' }
      )
    end

    it 'leaves a source_location that is not a hash alone' do
      attrs = { '__name' => 'web01', 'source_location' => nil }

      expect(described_class.strip(attrs)).to eq(attrs)
    end

    it 'removes the fleet-specific vars it is told about' do
      attrs = { '__name' => 'vm01!cpu', 'vars' => { 'see_esx_host' => { 'name' => 'esx01' }, 'keep' => 1 } }

      expect(described_class.strip(attrs, volatile_vars: ['see_esx_host']))
        .to eq('__name' => 'vm01!cpu', 'vars' => { 'keep' => 1 })
    end

    it 'keeps every var when told about none, since no default can know a fleet' do
      attrs = { '__name' => 'vm01!cpu', 'vars' => { 'see_esx_host' => { 'name' => 'esx01' } } }

      expect(described_class.strip(attrs)).to eq(attrs)
    end

    it 'does not mutate the hash it is given' do
      attrs = { '__name' => 'web01', 'last_check' => 1.0 }

      described_class.strip(attrs)

      expect(attrs).to have_key('last_check')
    end
  end
end
