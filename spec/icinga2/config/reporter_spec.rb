# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Icinga2::Config::Reporter do
  let(:buffer) { StringIO.new }

  # A StringIO is not a tty, so Console emits no escape codes and the expectations
  # below read as the user sees them when the output is piped.
  around do |example|
    original = $stdout
    $stdout = buffer
    example.run
  ensure
    $stdout = original
  end

  def object(name, **attrs)
    { '__name' => name }.merge(attrs.transform_keys(&:to_s))
  end

  def diff(old:, new:)
    Icinga2::Config::Diff.new(old: old, new: new)
  end

  def render(diff, **options)
    described_class.new(diff, **options).render
  end

  describe 'membership' do
    it 'lists what appeared and what disappeared, with a count for each' do
      render(diff(old: [object('b')], new: [object('a')]))

      expect(buffer.string).to include("  + 1 added\n      + a\n", "  - 1 removed\n      - b\n")
    end

    it 'says so plainly when nothing moved' do
      render(diff(old: [object('a')], new: [object('a')]))

      expect(buffer.string).to include('  no change')
    end
  end

  describe 'changed attributes' do
    it 'counts the objects each attribute changed on before detailing them' do
      report = diff(
        old: [object('a', period: '9to5'), object('b', period: '9to5')],
        new: [object('a', period: '24x7'), object('b', period: '24x7')]
      )

      render(report)

      expect(buffer.string).to include('  ~ 2 changed', 'period', '2 objects')
    end

    it 'shows the old and the new value of each change' do
      render(diff(old: [object('a', period: '9to5')], new: [object('a', period: '24x7')]))

      expect(buffer.string).to include(%(      ~ period: "9to5" -> "24x7"))
    end
  end

  describe 'the detail cap' do
    let(:many) do
      count = described_class::DETAIL_LIMIT + 5
      old = Array.new(count) { |i| object(format('host%02d', i), period: '9to5') }
      new = Array.new(count) { |i| object(format('host%02d', i), period: '24x7') }
      diff(old: old, new: new)
    end

    # A silent truncation reads as "that was everything".
    it 'details only the first 20 objects and announces the rest' do
      render(many)

      expect(buffer.string).to include('… and 5 more changed objects, use --all to list them')
      expect(buffer.string).to include('host19')
      expect(buffer.string).not_to include('host20')
    end

    it 'details every object with --all, and then has nothing left to announce' do
      render(many, all: true)

      expect(buffer.string).to include('host24')
      expect(buffer.string).not_to include('more changed objects')
    end
  end

  describe 'names_only' do
    it 'skips the attribute section entirely' do
      render(diff(old: [object('a', period: '9to5')], new: [object('a', period: '24x7')]), names_only: true)

      expect(buffer.string).not_to include('changed')
    end

    # This is what decides the exit code: comparing names only must not report a
    # difference because an attribute moved, or `--names-only` would exit 1 on
    # exactly the change it was asked to ignore.
    it 'reports no difference when only an attribute moved' do
      report = render(diff(old: [object('a', period: '9to5')], new: [object('a', period: '24x7')]),
                      names_only: true)

      expect(report.difference?).to be(false)
    end

    it 'still reports a difference when an object appeared' do
      report = render(diff(old: [], new: [object('a')]), names_only: true)

      expect(report.difference?).to be(true)
    end
  end

  describe '#difference?' do
    it 'is true when only an attribute moved, in the default mode' do
      report = render(diff(old: [object('a', period: '9to5')], new: [object('a', period: '24x7')]))

      expect(report.difference?).to be(true)
    end

    it 'is false when the two sides are identical' do
      expect(render(diff(old: [object('a')], new: [object('a')])).difference?).to be(false)
    end
  end

  # The caller chains `.render.difference?` to pick the exit code.
  it 'returns itself from render' do
    reporter = described_class.new(diff(old: [], new: []))

    expect(reporter.render).to be(reporter)
  end
end
