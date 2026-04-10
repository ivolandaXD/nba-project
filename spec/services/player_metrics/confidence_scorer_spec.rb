require 'rails_helper'

RSpec.describe PlayerMetrics::ConfidenceScorer do
  it 'returns score in 0..100' do
    s = described_class.call(
      coefficient_of_variation: 0.3,
      trend_last_10: 2.5,
      over_line_rate: 60,
      line: 20,
      over_20_rate: 50,
      streak_status: 'hot'
    )
    expect(s).to be_between(0, 100)
    expect(s).to be > 70
  end

  it 'penalizes cold streak and negative trend' do
    s = described_class.call(
      coefficient_of_variation: 0.9,
      trend_last_10: -3,
      over_line_rate: nil,
      line: nil,
      over_20_rate: 20,
      streak_status: 'cold'
    )
    expect(s).to be < 55
  end
end
