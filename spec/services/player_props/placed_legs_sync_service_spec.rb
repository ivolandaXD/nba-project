# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlayerProps::PlacedLegsSyncService do
  let(:user) { create(:user) }
  let(:game) { create(:game, home_team: 'LAL', away_team: 'BOS', game_date: Date.current) }
  let(:player) { create(:player, name: 'Sync Player', team: 'LAL', nba_player_id: 999_011) }

  before { allow(Nba::Season).to receive(:current).and_return('2025-26') }

  it 'creates legs with implied probability and edge from decimal odds' do
    placed =
      create(
        :placed_ai_suggestion,
        user: user,
        game: game,
        slip_kind: 'parlay',
        legs: [
          {
            'player' => player.name,
            'market' => 'PTS over',
            'line' => '10.5',
            'decimal_odds' => '2.0',
            'estimated_hit_probability' => 0.55
          }
        ]
      )

    described_class.call(placed)
    leg = placed.placed_ai_suggestion_legs.reload.first
    expect(leg).to be_present
    expect(leg.market_implied_probability).to be_within(1e-6).of(0.5)
    expect(leg.edge_percent_points).to be_within(0.01).of(5.0)
    expect(leg.team_abbr).to eq('LAL')
  end
end
