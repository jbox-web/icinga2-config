# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Icinga2::Config::Diff do
  def object(name, **attrs)
    { '__name' => name }.merge(attrs.transform_keys(&:to_s))
  end

  describe '#added / #removed' do
    it 'reports objects by name, in sorted order' do
      diff = described_class.new(old: [object('b')], new: [object('c'), object('a')])

      expect(diff.added).to eq(%w[a c])
      expect(diff.removed).to eq(%w[b])
    end
  end

  describe '#changed' do
    it 'reports the attribute path with its old and new value' do
      diff = described_class.new(
        old: [object('web01!ssh', period: '9to5')],
        new: [object('web01!ssh', period: '24x7')]
      )

      expect(diff.changed).to eq(
        'web01!ssh' => [{ op: '~', path: 'period', old: '9to5', new: '24x7' }]
      )
    end

    it 'reaches into nested attributes rather than reporting the whole vars hash' do
      diff = described_class.new(
        old: [object('web01', vars: { 'notification' => { 'mail' => { 'groups' => %w[admins] } } })],
        new: [object('web01', vars: { 'notification' => { 'mail' => { 'groups' => %w[exploit] } } })]
      )

      expect(diff.changed['web01'].first[:path]).to eq('vars.notification.mail.groups[0]')
    end

    it 'ignores objects that only exist on one side, which added/removed already report' do
      diff = described_class.new(old: [], new: [object('web01', period: '24x7')])

      expect(diff.changed).to be_empty
    end
  end

  describe '#summary' do
    it 'counts how many objects each attribute changed on, most frequent first' do
      diff = described_class.new(
        old: [object('a', period: '9to5', interval: 1800), object('b', period: '9to5')],
        new: [object('a', period: '24x7', interval: 86_400), object('b', period: '24x7')]
      )

      expect(diff.summary).to eq([['period', 2], ['interval', 1]])
    end
  end

  describe '#any?' do
    it 'is false when nothing moved' do
      expect(described_class.new(old: [object('a')], new: [object('a')]).any?).to be(false)
    end

    it 'is true when only an attribute moved' do
      diff = described_class.new(old: [object('a', period: '9to5')], new: [object('a', period: '24x7')])

      expect(diff.any?).to be(true)
    end
  end
end
