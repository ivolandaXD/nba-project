# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlayerProps::PostMortemPayloadBuilder do
  let(:user) { create(:user) }
  let(:game) { create(:game, home_team: 'LAL', away_team: 'BOS', game_date: Date.current) }
  let(:player) { create(:player, name: 'Weak Match', team: 'LAL', nba_player_id: 999_014) }

  before { allow(Nba::Season).to receive(:current).and_return('2025-26') }

  it 'flags review_confidence_penalty when matching is weak (ex.: jogador não resolvido)' do
    player
    placed =
      create(
        :placed_ai_suggestion,
        user: user,
        game: game,
        slip_kind: 'parlay',
        legs: [{ 'player' => 'Jogador Inexistente ZZZ999', 'market' => 'PTS', 'line' => '5.5' }]
      )

    payload = described_class.call(placed)
    dq = payload[:data_quality]
    expect(dq[:weak_match_leg_count]).to be >= 1
    expect(dq[:review_confidence_penalty]).to be true
  end
end
