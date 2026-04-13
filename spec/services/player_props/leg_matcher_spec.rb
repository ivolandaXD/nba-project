# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlayerProps::LegMatcher do
  let(:game) { create(:game, home_team: 'LAL', away_team: 'BOS', game_date: Date.current) }
  let(:player) { create(:player, name: 'Test Roster', team: 'LAL', nba_player_id: 999_001) }
  let(:placed) { create(:placed_ai_suggestion, game: game, slip_kind: 'single', legs: []) }

  before do
    allow(Nba::Season).to receive(:current).and_return('2025-26')
  end

  it 'matches exact name against roster' do
    player # garante persistência antes do matcher consultar o elenco
    res = described_class.call(
      placed: placed,
      leg_hash: { 'player' => 'Test Roster', 'market' => 'PTS', 'line' => 10 },
      leg_index: 0
    )
    expect(res.player_id).to eq(player.id)
    expect(res.match_method).to eq('exact_name')
    expect(res.matched_confidence).to eq(1.0)
    expect(res.game_id).to eq(game.id)
  end
end
