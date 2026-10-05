# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Icinga2::Config::Store do
  subject(:store) { described_class.new(root) }

  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  attr_reader :root

  def make_snapshot(name, objects: Icinga2::Config::DEFAULT_OBJECTS, extension: 'jsonl')
    dir = File.join(root, name)
    Dir.mkdir(dir)
    objects.each { |object| File.write(File.join(dir, "#{object}.#{extension}"), "{}\n") }
    dir
  end

  describe '#all' do
    it 'lists snapshots in chronological order, which the timestamp names make lexicographic' do
      make_snapshot('20260814-010000')
      make_snapshot('20260813-235959')

      expect(store.all.map { |s| File.basename(s) }).to eq(%w[20260813-235959 20260814-010000])
    end

    it 'returns nothing when the directory does not exist yet' do
      expect(described_class.new(File.join(root, 'absent')).all).to eq([])
    end
  end

  describe '#resolve' do
    it 'resolves latest and prev' do
      make_snapshot('20260813-235959')
      make_snapshot('20260814-010000')

      expect(File.basename(store.resolve('latest'))).to eq('20260814-010000')
      expect(File.basename(store.resolve('prev'))).to eq('20260813-235959')
    end

    it 'resolves a snapshot name' do
      make_snapshot('20260814-010000')

      expect(File.basename(store.resolve('20260814-010000'))).to eq('20260814-010000')
    end

    it 'resolves a path that lies outside the snapshot root' do
      Dir.mktmpdir do |elsewhere|
        expect(store.resolve(elsewhere)).to eq(elsewhere)
      end
    end

    it 'raises a usage error naming what is available when the reference is unknown' do
      make_snapshot('20260814-010000')

      expect { store.resolve('nope') }
        .to raise_error(Icinga2::Config::UsageError, /nope.*20260814-010000/m)
    end
  end

  describe '#read' do
    it 'reads a JSON Lines file into an array of hashes' do
      dir = File.join(root, '20260814-010000')
      Dir.mkdir(dir)
      File.write(File.join(dir, 'hosts.jsonl'), %({"__name":"a"}\n{"__name":"b"}\n))

      expect(store.read(dir, 'hosts')).to eq([{ '__name' => 'a' }, { '__name' => 'b' }])
    end

    it 'refuses a snapshot written by the previous bash tool instead of failing on a parse error' do
      make_snapshot('20260813-203340', extension: 'json')

      expect { store.read(File.join(root, '20260813-203340'), 'hosts') }
        .to raise_error(Icinga2::Config::UsageError, /previous/i)
    end

    it 'reports a missing object file rather than reporting no change' do
      make_snapshot('20260814-010000', objects: %w[hosts])

      expect { store.read(File.join(root, '20260814-010000'), 'services') }
        .to raise_error(Icinga2::Config::UsageError, /incomplete/i)
    end
  end

  # What makes two snapshots taken with different `objects:` lists comparable:
  # the diff runs on the intersection of what each one actually carries.
  describe '#types' do
    it 'lists the object types a snapshot carries, sorted' do
      dir = make_snapshot('20260814-010000', objects: %w[timeperiods hosts])

      expect(store.types(dir)).to eq(%w[hosts timeperiods])
    end

    it 'lists only what is there, for a snapshot taken with a narrower list' do
      dir = make_snapshot('20260814-010000', objects: %w[hosts])

      expect(store.types(dir)).to eq(%w[hosts])
    end

    it 'is empty for a directory holding no snapshot file' do
      dir = File.join(root, 'empty')
      Dir.mkdir(dir)

      expect(store.types(dir)).to eq([])
    end

    # A `.json` file is the previous bash tool's output, which #read refuses; it
    # must not be counted as a comparable type either.
    it 'ignores files that are not JSON Lines' do
      dir = make_snapshot('20260813-203340', extension: 'json')

      expect(store.types(dir)).to eq([])
    end
  end
end
