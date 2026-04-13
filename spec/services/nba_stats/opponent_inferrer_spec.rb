# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NbaStats::OpponentInferrer do
  describe '.canonical_abbr' do
    it 'maps GS to GSW (Golden State)' do
      expect(described_class.canonical_abbr('GS')).to eq('GSW')
      expect(described_class.canonical_abbr('gs')).to eq('GSW')
    end

    it 'leaves GSW unchanged' do
      expect(described_class.canonical_abbr('GSW')).to eq('GSW')
    end
  end
end
