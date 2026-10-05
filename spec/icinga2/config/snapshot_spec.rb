# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Icinga2::Config::Snapshot do
  subject(:snapshot) { described_class.new(store: Icinga2::Config::Store.new(root), client: client) }

  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  attr_reader :root

  let(:client) { instance_double(Icinga2::API::Client) }
  let(:collection) { instance_double(Icinga2::API::Objects) }
  let(:timestamp) { '20260814-012201' }
  let(:directory) { File.join(root, timestamp) }

  before { allow(client).to receive(:objects).and_return(collection) }

  # What `Objects#all` hands the builder block: the raw `attrs` hash, string
  # keys, with the entries carrying no `attrs` already dropped.
  def entry(name)
    { '__name' => name, 'state' => 2 }
  end

  # `Objects#all` applies the builder block to each object's attrs. A stub that
  # returned a canned array would never call it, leaving the identity block —
  # the one thing keeping the keys as strings instead of a Host object — untested.
  def stub_all(double, entries)
    allow(double).to receive(:all) { |&builder| entries.map { |attrs| builder.call(attrs) } }
  end

  it 'writes one JSON Lines file per object type, with the volatile attributes stripped' do
    stub_all(collection, [entry('a')])

    snapshot.take(timestamp)

    expect(File.read(File.join(directory, 'hosts.jsonl'))).to eq(%({"__name":"a"}\n))
  end

  # Icinga returns arrays all over the place (`groups`, `templates`, custom vars
  # holding a list of hashes). Sorting only the top level would leave those hashes
  # in whatever order the API sent them, and two snapshots of an unchanged
  # configuration would stop being byte-identical.
  it 'sorts keys inside hashes nested in an array' do
    stub_all(collection, [{ 'vars' => { 'disks' => [{ 'warn' => 80, 'path' => '/' }] }, '__name' => 'a' }])

    snapshot.take(timestamp)

    expect(File.read(File.join(directory, 'hosts.jsonl')))
      .to eq(%({"__name":"a","vars":{"disks":[{"path":"/","warn":80}]}}\n))
  end

  it 'leaves no partial file behind' do
    stub_all(collection, [entry('a')])

    snapshot.take(timestamp)

    expect(Dir.children(directory)).to contain_exactly('hosts.jsonl', 'services.jsonl', 'notifications.jsonl')
  end

  it 'refuses an empty answer rather than writing an empty snapshot' do
    stub_all(collection, [])

    expect { snapshot.take(timestamp) }.to raise_error(Icinga2::Config::UsageError, /No hosts returned/)
  end

  # Otherwise the empty shell becomes `latest`, and the next diff resolves to it.
  it 'removes the directory it created when nothing could be fetched' do
    allow(collection).to receive(:all).and_raise(StandardError, 'connection refused')

    expect { snapshot.take(timestamp) }.to raise_error(StandardError)
    expect(Dir.exist?(directory)).to be(false)
  end

  it 'keeps what it managed to write when a later object type fails' do
    failing = instance_double(Icinga2::API::Objects)
    allow(client).to receive(:objects).with(:host).and_return(collection)
    allow(client).to receive(:objects).with(:service).and_return(failing)
    stub_all(collection, [entry('a')])
    allow(failing).to receive(:all).and_raise(StandardError, 'timeout')

    expect { snapshot.take(timestamp) }.to raise_error(StandardError)
    expect(Dir.children(directory)).to eq(['hosts.jsonl'])
  end

  # The catalog only answers to the singular symbol and rejects the plural
  # endpoint name locally, so fetching by file name would fail before any
  # request went out.
  it 'asks the catalog for the singular Icinga type, not the endpoint name' do
    stub_all(collection, [entry('a')])

    snapshot.take(timestamp)

    expect(client).to have_received(:objects).with(:host)
    expect(client).to have_received(:objects).with(:notification)
  end

  # How the CLI drives its spinner without Snapshot knowing anything about the
  # terminal: it is handed each type just before that type is fetched.
  describe 'progress reporting' do
    it 'yields each type, in order, before fetching it' do
      stub_all(collection, [entry('a')])
      seen = []

      snapshot.take(timestamp) { |object| seen << object }

      expect(seen).to eq(%w[hosts services notifications])
    end

    it 'takes the snapshot just the same when no block is given' do
      stub_all(collection, [entry('a')])

      expect { snapshot.take(timestamp) }.not_to raise_error
      expect(Dir.children(directory)).to include('hosts.jsonl')
    end
  end

  context 'with a configured subset' do
    subject(:snapshot) do
      described_class.new(store: Icinga2::Config::Store.new(root), client: client,
                          objects: %w[hosts timeperiods])
    end

    it 'fetches only the configured types, and no other' do
      stub_all(collection, [entry('a')])

      snapshot.take(timestamp)

      expect(client).to have_received(:objects).with(:host)
      expect(client).to have_received(:objects).with(:time_period)
      expect(client).not_to have_received(:objects).with(:service)
    end

    it 'writes one file per configured type, and no other' do
      stub_all(collection, [entry('a')])

      snapshot.take(timestamp)

      expect(Dir.children(directory)).to contain_exactly('hosts.jsonl', 'timeperiods.jsonl')
    end
  end
end
