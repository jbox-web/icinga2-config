# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Icinga2::Config::Spinner do
  subject(:host) { Class.new { include Icinga2::Config::Spinner }.new }

  # Whirly decides whether to draw by asking the stream `tty?`, and defaults to
  # `$stdout`. Swapping it is the only way to exercise both branches.
  let(:buffer) { StringIO.new }

  around do |example|
    original = $stdout
    $stdout = buffer
    example.run
  ensure
    $stdout = original
    Whirly.stop
  end

  def terminal!
    allow(buffer).to receive(:tty?).and_return(true)
  end

  # The reason this module exists rather than a plain `Whirly.start { }`: off a
  # terminal, whirly returns before calling its block, so the block form would
  # silently skip the work under cron and still exit 0.
  it 'runs the work when the output is not a terminal' do
    ran = false

    host.with_spinner { ran = true }

    expect(ran).to be(true)
  end

  it 'runs the work on a terminal too' do
    terminal!
    ran = false

    host.with_spinner { ran = true }

    expect(ran).to be(true)
  end

  it 'returns what the work returned' do
    expect(host.with_spinner { 'the snapshot' }).to eq('the snapshot')
  end

  # Snapshot raises UsageError and Icinga2::API::Error, and the CLI turns those
  # into exit 2. A spinner that swallowed them would break that contract.
  it 'lets an exception through, and still stops the spinner' do
    terminal!

    expect { host.with_spinner { raise Icinga2::Config::UsageError, 'boom' } }
      .to raise_error(Icinga2::Config::UsageError, 'boom')

    # Whirly refuses to start again while it believes it is already running, so
    # a second run doing its work proves the first one was stopped.
    ran_again = false
    host.with_spinner { ran_again = true }
    expect(ran_again).to be(true)
  end

  it 'draws nothing off a terminal, so a redirected run stays clean' do
    host.with_spinner { |report| report.call('hosts') }

    expect(buffer.string).to eq('')
  end

  # Whirly prints the show-cursor sequence from `stop`, so its presence is the
  # observable proof that the ensure ran. Without it a crashed run would leave the
  # user's terminal with no cursor.
  it 'restores the cursor even when the work raises' do
    terminal!

    expect { host.with_spinner { raise Icinga2::Config::UsageError, 'boom' } }.to raise_error(StandardError)

    expect(buffer.string).to include("\e[?25h")
  end

  # paint colours through whirly, not through Console, so NO_COLOR would sail past
  # it unless the option is wired to Console#color?.
  it 'honours NO_COLOR on a terminal' do
    terminal!
    saved = ENV.fetch('NO_COLOR', nil)
    ENV['NO_COLOR'] = '1'

    begin
      host.with_spinner { sleep 0.3 }
    ensure
      saved.nil? ? ENV.delete('NO_COLOR') : ENV['NO_COLOR'] = saved
    end

    expect(buffer.string).not_to match(/\e\[[0-9;]*m/)
  end

  # Otherwise the last frame stays on screen: "⠹ fetching notifications" frozen
  # right above a summary saying every type is in.
  it 'wipes the status line on the way out' do
    terminal!

    host.with_spinner do |report|
      report.call('notifications')
      sleep 0.3
    end

    # Whirly redraws between \e7 (save cursor) and \e8 (restore). After the wipe
    # the last of those pairs must carry nothing but blanks.
    last_draw = buffer.string.split("\e7").last.to_s.split("\e8").first.to_s

    expect(last_draw).not_to include('fetching')
    expect(last_draw.strip).to eq('')
  end

  it 'shows each step it is handed, on a terminal' do
    terminal!

    # Whirly redraws from its own thread on an interval, so the status only
    # reaches the stream if the work outlasts a tick.
    host.with_spinner do |report|
      report.call('hosts')
      sleep 0.3
    end

    expect(buffer.string).to include('fetching hosts')
  end
end
