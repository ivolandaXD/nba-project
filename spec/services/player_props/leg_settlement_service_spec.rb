# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlayerProps::LegSettlementService do
  let(:user) { create(:user) }
  let(:game) { create(:game, home_team: 'LAL', away_team: 'BOS', game_date: Date.current) }
  let(:player) { create(:player, name: 'Box Player', team: 'LAL', nba_player_id: 999_012) }

  before { allow(Nba::Season).to receive(:current).and_return('2025-26') }

  it 'settles over hit with actual_value and delta' do
    create(:player_game_stat, player: player, game: game, points: 25, rebounds: 4)

    placed =
      create(
        :placed_ai_suggestion,
        user: user,
        game: game,
        slip_kind: 'parlay',
        legs: [
          { 'player' => player.name, 'market' => 'PTS', 'line' => '20.5' }
        ]
      )

    PlayerProps::PlacedLegsSyncService.call(placed)
    described_class.call(placed)

    leg = placed.placed_ai_suggestion_legs.reload.first
    expect(leg.result_status).to eq('hit')
    expect(leg.actual_value.to_f).to eq(25.0)
    expect(leg.delta_vs_line.to_f).to be_within(0.01).of(4.5)
  end
end
