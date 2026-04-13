# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlayerProps::DecimalOdds do
  describe '.implied_probability' do
    it 'returns 1/decimal for EU odds' do
      expect(described_class.implied_probability(2.0)).to be_within(1e-6).of(0.5)
    end

    it 'returns nil for invalid decimal' do
      expect(described_class.implied_probability(1.0)).to be_nil
    end
  end

  describe '.edge_percent_points' do
    it 'computes difference in percentage points' do
      edge = described_class.edge_percent_points(estimated_probability: 0.58, decimal_odds: 2.0)
      expect(edge).to be_within(1e-6).of(8.0)
    end
  end
end
