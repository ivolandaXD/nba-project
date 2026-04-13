# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AnalysisModes do
  it 'maps legacy modes to canonical' do
    expect(described_class.canonical('props_portfolio')).to eq(described_class::PREGAME_PORTFOLIO)
    expect(described_class.canonical('points_props_pro')).to eq(described_class::PREGAME_SINGLE_MARKET)
    expect(described_class.canonical('post_mortem_bet_review')).to eq(described_class::POSTGAME_REVIEW)
  end

  it 'marks legacy keys as deprecated' do
    expect(described_class.deprecated?('props_portfolio')).to be true
    expect(described_class.deprecated?(described_class::PREGAME_PORTFOLIO)).to be false
  end

  it 'routes predicates without duplicating string branches' do
    expect(described_class.postgame_review?('post_mortem_bet_review')).to be true
    expect(described_class.pregame_portfolio?('props_portfolio')).to be true
    expect(described_class.pregame_single_market_pro?('points_props_pro', {})).to be true
    expect(described_class.pregame_single_market_pro?('pregame_single_market', { decision_score: 1 })).to be true
    expect(described_class.pregame_single_market_pro?('pregame_single_market', {})).to be false
  end
end
