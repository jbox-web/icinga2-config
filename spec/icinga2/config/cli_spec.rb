# frozen_string_literal: true

require 'spec_helper'
require 'icinga2/config/cli'
require 'tmpdir'
require 'stringio'

RSpec.describe Icinga2::Config::CLI do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      saved = ENV.fetch('ICINGA_SNAPSHOT_DIR', nil)
      ENV['ICINGA_SNAPSHOT_DIR'] = dir
      begin
        example.run
      ensure
        saved.nil? ? ENV.delete('ICINGA_SNAPSHOT_DIR') : ENV['ICINGA_SNAPSHOT_DIR'] = saved
      end
    end
  end

  attr_reader :root

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  # `extra` carries the types beyond the default three, for the examples about
  # snapshots taken with different `objects:` lists.
  def write_snapshot(name, hosts:, **extra)
    directory = File.join(root, name)
    FileUtils.mkdir_p(directory)
    files = { 'hosts' => hosts, 'services' => [], 'notifications' => [] }.merge(extra.transform_keys(&:to_s))
    files.each do |object, entries|
      File.write(File.join(directory, "#{object}.jsonl"), entries.map { |e| "#{JSON.generate(e)}\n" }.join)
    end
  end

  def object(name, **attrs)
    { '__name' => name }.merge(attrs.transform_keys(&:to_s))
  end

  # Returns the exit status the CLI would hand the shell: 0 when the command
  # returns normally, otherwise whatever it exited with.
  def run(*argv)
    original_out = $stdout
    original_err = $stderr
    $stdout = out
    $stderr = err
    begin
      described_class.start(argv)
      0
    rescue SystemExit => e
      e.status
    end
  ensure
    $stdout = original_out
    $stderr = original_err
  end

  describe 'diff exit codes' do
    # The contract a cron job depends on: 0 no difference, 1 difference, 2 usage
    # error. A usage error exiting 1 would read as "the configuration changed".
    it 'exits 0 when the two snapshots agree' do
      write_snapshot('20260101-000000', hosts: [object('a', period: '24x7')])
      write_snapshot('20260102-000000', hosts: [object('a', period: '24x7')])

      expect(run('diff')).to eq(0)
    end

    it 'exits 1 when an attribute changed' do
      write_snapshot('20260101-000000', hosts: [object('a', period: '9to5')])
      write_snapshot('20260102-000000', hosts: [object('a', period: '24x7')])

      expect(run('diff')).to eq(1)
    end

    it 'exits 2, not 1, when the reference cannot be resolved' do
      write_snapshot('20260101-000000', hosts: [object('a')])

      expect(run('diff', 'nonexistent', 'latest')).to eq(2)
    end

    it 'exits 2 when fewer than two snapshots exist' do
      write_snapshot('20260101-000000', hosts: [object('a')])

      expect(run('diff')).to eq(2)
    end

    it 'exits 2 on an unknown object type, naming the ones it accepts' do
      write_snapshot('20260101-000000', hosts: [object('a')])
      write_snapshot('20260102-000000', hosts: [object('a')])

      expect(run('diff', '--object', 'bogus')).to eq(2)
      expect(err.string).to include('hosts, services, notifications')
    end
  end

  describe 'diff options' do
    before do
      write_snapshot('20260101-000000', hosts: [object('a', period: '9to5')])
      write_snapshot('20260102-000000', hosts: [object('b', period: '24x7')])
    end

    it 'restricts the comparison to the requested object type' do
      run('diff', '--object', 'hosts')

      expect(out.string).to include('hosts')
      expect(out.string).not_to include('notifications')
    end

    it 'accepts explicit snapshot names as well as latest and prev' do
      expect(run('diff', '20260101-000000', '20260102-000000')).to eq(1)
      expect(out.string).to include('Comparing 20260101-000000 -> 20260102-000000')
    end
  end

  # Widening `objects:` must not make every earlier snapshot uncomparable: the
  # first diff after the change would otherwise exit 2 with nothing having moved
  # in the configuration.
  describe 'snapshots carrying different types' do
    before do
      write_snapshot('20260101-000000', hosts: [object('a', period: '9to5')])
      write_snapshot('20260102-000000', hosts: [object('a', period: '9to5')], timeperiods: [object('24x7')])
    end

    it 'compares the types both sides carry instead of failing on the missing one' do
      expect(run('diff')).to eq(0)
    end

    it 'still detects a difference within the shared types' do
      write_snapshot('20260103-000000', hosts: [object('a', period: '24x7')], timeperiods: [object('24x7')])

      expect(run('diff')).to eq(1)
    end

    # A silent skip reads as "those types are identical".
    it 'announces the types it could not compare' do
      run('diff')

      expect(out.string).to include('timeperiods')
      expect(out.string).to match(/skipped/i)
    end

    # Asserts the wording, not just the exit code: Store#read would raise on the
    # missing file anyway, so a test matching only on the type name would pass
    # with the explicit check deleted, and stop protecting anything.
    it 'exits 2 when --object names a type only one side carries' do
      expect(run('diff', '--object', 'timeperiods')).to eq(2)
      expect(err.string).to include("'timeperiods' is missing from one of the two snapshots")
    end

    # Validated against the catalogue, not against the configured list, so a type
    # dropped from `objects:` since a snapshot was taken stays diffable.
    it 'accepts a --object that is capturable but not currently configured' do
      write_snapshot('20260103-000000', hosts: [object('a')], timeperiods: [object('24x7')])
      write_snapshot('20260104-000000', hosts: [object('a')], timeperiods: [object('24x7')])

      expect(run('diff', '--object', 'timeperiods')).to eq(0)
    end
  end

  describe 'completion' do
    # Asserts on a marker only that shell's script carries: matching the
    # executable name alone would pass with both generators swapped, and the user
    # would install a zsh script into bash.
    it 'prints a zsh script' do
      expect(run('completion', 'zsh')).to eq(0)

      expect(out.string).to include('#compdef', 'icinga-config')
      expect(out.string).not_to include('COMPREPLY')
    end

    it 'prints a bash script' do
      expect(run('completion', 'bash')).to eq(0)

      expect(out.string).to include('COMPREPLY', 'icinga-config')
      expect(out.string).not_to include('#compdef')
    end

    # The script is piped into a file or sourced, so it must be the only thing on
    # stdout — a stray banner would end up inside the completion function.
    it 'writes the script and nothing else' do
      run('completion', 'zsh')

      expect(out.string).not_to include('Snapshotting', 'Comparing')
    end

    it 'covers the commands it completes' do
      run('completion', 'zsh')

      expect(out.string).to include('snapshot', 'diff', 'list', 'state')
    end

    it 'exits 2 on a shell it cannot generate for, naming the ones it can' do
      expect(run('completion', 'fish')).to eq(2)
      expect(err.string).to include('fish', 'zsh', 'bash')
    end
  end

  describe 'list' do
    it 'prints one line per snapshot with a count per object type' do
      write_snapshot('20260101-000000', hosts: [object('a'), object('b')])

      run('list')

      expect(out.string).to include('20260101-000000', 'hosts=2', 'services=0')
    end

    it 'points at the snapshot command when there is nothing to list' do
      run('list')

      expect(out.string).to include('run `icinga-config snapshot` first')
    end

    # Saying nothing would read as a snapshot that carries nothing, rather than
    # one that could not be read at all.
    it 'marks a snapshot carrying no object file as unreadable instead of listing it blank' do
      FileUtils.mkdir_p(File.join(root, '20260101-000000'))

      run('list')

      expect(out.string).to include('20260101-000000', 'unreadable')
    end

    it 'lists only the types a snapshot actually carries' do
      write_snapshot('20260101-000000', hosts: [object('a')], timeperiods: [object('24x7')])

      run('list')

      expect(out.string).to include('hosts=1', 'timeperiods=1')
    end
  end

  describe 'snapshot' do
    let(:client) { instance_double(Icinga2::API::Client) }
    let(:collection) { instance_double(Icinga2::API::Objects) }

    before do
      allow(Icinga2::Config::Client).to receive(:build).and_return(client)
      allow(client).to receive(:objects).and_return(collection)
    end

    it 'reports the destination and a count per object type' do
      allow(collection).to receive(:all) { |&builder| [builder.call('__name' => 'a', 'state' => 2)] }

      expect(run('snapshot')).to eq(0)
      expect(out.string).to include('hosts', '1 objects', 'Snapshot written to')
    end

    # Whirly skips its block entirely when the stream is not a terminal, so the
    # fetch must never live inside it: under cron that would take no snapshot at
    # all and still exit 0. The spinner is started and stopped around the work.
    it 'takes the snapshot when the output is not a terminal' do
      allow(collection).to receive(:all) { |&builder| [builder.call('__name' => 'a')] }

      expect(run('snapshot')).to eq(0)
      expect(Dir.children(File.join(root, Dir.children(root).first))).to include('hosts.jsonl')
    end

    it 'writes no escape sequence when the output is not a terminal' do
      allow(collection).to receive(:all) { |&builder| [builder.call('__name' => 'a')] }

      run('snapshot')

      expect(out.string).not_to include("\e[")
    end

    it 'exits 2 when the API returns nothing, rather than writing an empty snapshot' do
      allow(collection).to receive(:all).and_return([])

      expect(run('snapshot')).to eq(2)
      expect(err.string).to include('check the credentials')
    end

    # An unreachable master used to escape as a backtrace on a status that was
    # neither 0, 1 nor 2 — which a cron job cannot classify.
    it 'exits 2 with an actionable message when the master cannot be reached' do
      allow(collection).to receive(:all).and_raise(
        Icinga2::API::Error::ConnectionFailed, 'Failed to open TCP connection'
      )

      expect(run('snapshot')).to eq(2)
      expect(err.string).to include('Cannot reach the Icinga 2 API', 'ICINGA_API_HOST')
      expect(err.string).not_to include('backtrace')
    end

    it 'exits 2 and points at the credentials when the master rejects the request' do
      allow(collection).to receive(:all).and_raise(Icinga2::API::Error::ClientError, '401 Unauthorized')

      expect(run('snapshot')).to eq(2)
      expect(err.string).to include('ICINGA_API_USER', 'ICINGA_API_PASS')
    end
  end

  describe 'state' do
    # `name` and the attribute readers reach Host through method_missing, so a
    # verifying double cannot stand in for it here.
    let(:host) { double('Host') } # rubocop:disable RSpec/VerifiedDoubles
    let(:hosts) { instance_double(Icinga2::API::Hosts) }
    let(:client) { instance_double(Icinga2::API::Client, hosts: hosts) }

    let(:attributes) do
      {
        __name: 'web01',
        state: 2,
        state_type: 1,
        check_attempt: 3,
        max_check_attempts: 3,
        last_state_change: 1_767_225_600.0,
        last_check_result: { 'output' => 'CRITICAL - load average: 12', 'command' => %w[check_load -w 5] }
      }
    end

    before { allow(Icinga2::Config::Client).to receive(:build).and_return(client) }

    it 'prints the runtime state a snapshot deliberately strips' do
      allow(hosts).to receive(:find).with('web01').and_return(host)
      allow(host).to receive(:to_hash).and_return(attributes)

      expect(run('state', 'web01')).to eq(0)
      expect(out.string).to include('2 — CRITICAL (hard)', '3/3', 'CRITICAL - load average: 12', 'check_load -w 5')
    end

    it 'exits 2 when the host does not exist' do
      allow(hosts).to receive(:find).with('nope').and_return(nil)

      expect(run('state', 'nope')).to eq(2)
      expect(err.string).to include("Host 'nope' not found")
    end

    it 'exits 2 with an actionable message when the master is unreachable' do
      allow(hosts).to receive(:find).and_raise(Icinga2::API::Error::ConnectionFailed, 'connection refused')

      expect(run('state', 'web01')).to eq(2)
      expect(err.string).to include('Cannot reach the Icinga 2 API')
    end

    it 'exits 2 when the service does not exist on that host' do
      services = instance_double(Icinga2::API::Services)
      allow(hosts).to receive(:find).with('web01').and_return(host)
      allow(host).to receive_messages(services: services, name: 'web01')
      allow(services).to receive(:find).with('nope').and_return(nil)

      expect(run('state', 'web01', 'nope')).to eq(2)
      expect(err.string).to include("Service 'nope' not found on web01")
    end
  end
end
