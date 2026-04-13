# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlacedAiSuggestionLeg, type: :model do
  it 'is valid with required attributes' do
    user = create(:user)
    game = create(:game)
    placed = create(:placed_ai_suggestion, user: user, game: game, slip_kind: 'parlay', legs: [{ 'player' => 'X', 'market' => 'PTS', 'line' => 1 }])
    leg = described_class.new(
      placed_ai_suggestion: placed,
      leg_index: 0,
      sport: 'nba',
      market_type: 'points',
      selection_type: 'over',
      line_value: 20.5,
      result_status: 'pending',
      matched_confidence: 0.95,
      match_method: 'exact_name',
      source_payload: {},
      metadata: {}
    )
    expect(leg).to be_valid
  end

  it 'rejects matched_confidence out of range' do
    user = create(:user)
    game = create(:game)
    placed = create(:placed_ai_suggestion, user: user, game: game, slip_kind: 'parlay', legs: [{ 'player' => 'X', 'market' => 'PTS', 'line' => 1 }])
    leg = described_class.new(
      placed_ai_suggestion: placed,
      leg_index: 0,
      sport: 'nba',
      market_type: 'points',
      result_status: 'pending',
      matched_confidence: 1.5,
      source_payload: {},
      metadata: {}
    )
    expect(leg).not_to be_valid
  end
end
