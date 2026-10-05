# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Icinga2::Config::Settings do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = File.realpath(dir)
      example.run
    end
  end

  attr_reader :dir

  def write_config(content, at: dir)
    File.write(File.join(at, described_class::FILENAME), content)
  end

  describe '.discover' do
    it 'reads the file sitting in the given directory' do
      write_config("snapshot_dir: elsewhere\n")

      expect(described_class.discover(dir).snapshot_dir).to eq(File.join(dir, 'elsewhere'))
    end

    it 'walks up until it finds one, so the tool works from a subdirectory' do
      write_config("snapshot_dir: elsewhere\n")
      deep = File.join(dir, 'a', 'b')
      FileUtils.mkdir_p(deep)

      expect(described_class.discover(deep).snapshot_dir).to eq(File.join(dir, 'elsewhere'))
    end

    it 'falls back to defaults when no file is found anywhere above' do
      settings = described_class.discover(dir)

      expect(settings.snapshot_dir).to eq(File.join(dir, 'snapshots'))
      expect(settings.volatile_vars).to eq([])
    end

    it 'refuses a file that is not a mapping instead of silently ignoring it' do
      write_config("- just\n- a list\n")

      expect { described_class.discover(dir) }.to raise_error(Icinga2::Config::UsageError, /mapping/i)
    end
  end

  describe '#snapshot_dir' do
    it 'lets the environment win over the file' do
      write_config("snapshot_dir: from_file\n")

      expect(described_class.discover(dir, env: { 'ICINGA_SNAPSHOT_DIR' => '/tmp/from_env' }).snapshot_dir)
        .to eq('/tmp/from_env')
    end

    it 'keeps an absolute path from the file as it is' do
      write_config("snapshot_dir: /var/lib/icinga-snapshots\n")

      expect(described_class.discover(dir).snapshot_dir).to eq('/var/lib/icinga-snapshots')
    end
  end

  describe '#volatile_vars' do
    it 'reads the fleet-specific vars to strip, which no generic default can know' do
      write_config("volatile_vars:\n  - see_esx_host\n")

      expect(described_class.discover(dir).volatile_vars).to eq(['see_esx_host'])
    end
  end

  describe '#objects' do
    # Extending TYPES must never change what an existing installation writes.
    it 'captures the three historical types when nothing is configured' do
      expect(described_class.discover(dir).objects).to eq(%w[hosts services notifications])
    end

    it 'takes the configured list, in the order it is written' do
      write_config("objects:\n  - hosts\n  - timeperiods\n")

      expect(described_class.discover(dir).objects).to eq(%w[hosts timeperiods])
    end

    # Caught here rather than at fetch time: the catalog would reject it too, but
    # only after the snapshot directory had been created.
    it 'refuses a type that cannot be captured, and names the ones that can' do
      write_config("objects:\n  - downtimes\n")

      expect { described_class.discover(dir).objects }
        .to raise_error(Icinga2::Config::UsageError, /downtimes.*hosts/m)
    end

    it 'refuses a value that is not a list' do
      write_config("objects: hosts\n")

      expect { described_class.discover(dir).objects }.to raise_error(Icinga2::Config::UsageError, /list/i)
    end

    it 'refuses an empty list rather than writing a snapshot with no file in it' do
      write_config("objects: []\n")

      expect { described_class.discover(dir).objects }.to raise_error(Icinga2::Config::UsageError, /empty/i)
    end
  end
end
