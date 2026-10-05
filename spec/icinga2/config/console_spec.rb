# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Icinga2::Config::Console do
  subject(:console) { Class.new { include Icinga2::Config::Console }.new }

  let(:buffer) { StringIO.new }

  # `$stdout` is what Console writes to and what it asks `tty?`, so both the
  # capture and the colour decision go through the same swapped object.
  around do |example|
    original = $stdout
    $stdout = buffer
    example.run
  ensure
    $stdout = original
  end

  around do |example|
    saved = ENV.fetch('NO_COLOR', nil)
    example.run
  ensure
    saved.nil? ? ENV.delete('NO_COLOR') : ENV['NO_COLOR'] = saved
  end

  def tty!(value)
    allow(buffer).to receive(:tty?).and_return(value)
  end

  describe '#color?' do
    it 'is true on a terminal with NO_COLOR unset' do
      tty!(true)
      ENV.delete('NO_COLOR')

      expect(console.color?).to be(true)
    end

    it 'is false when the output is redirected, so a piped diff stays greppable' do
      tty!(false)
      ENV.delete('NO_COLOR')

      expect(console.color?).to be(false)
    end

    # Honoured by presence, not by value: NO_COLOR= (empty) still means no colour.
    it 'is false when NO_COLOR is set, even to an empty string' do
      tty!(true)
      ENV['NO_COLOR'] = ''

      expect(console.color?).to be(false)
    end
  end

  describe '#paint' do
    it 'wraps the text in the escape code of the requested style' do
      tty!(true)
      ENV.delete('NO_COLOR')

      expect(console.paint('boom', :red)).to eq("\e[31mboom\e[0m")
    end

    it 'returns the bare text when colour is off' do
      tty!(false)

      expect(console.paint('boom', :red)).to eq('boom')
    end

    it 'raises on an unknown style rather than emitting a broken escape sequence' do
      tty!(true)
      ENV.delete('NO_COLOR')

      expect { console.paint('boom', :chartreuse) }.to raise_error(KeyError)
    end
  end

  describe '#line' do
    it 'writes the text unstyled when no style is given' do
      tty!(true)
      console.line('plain')

      expect(buffer.string).to eq("plain\n")
    end

    it 'writes an empty line when called with no argument' do
      tty!(false)
      console.line

      expect(buffer.string).to eq("\n")
    end

    it 'paints the text when a style is given' do
      tty!(true)
      ENV.delete('NO_COLOR')
      console.line('done', style: :green)

      expect(buffer.string).to eq("\e[32mdone\e[0m\n")
    end
  end
end
