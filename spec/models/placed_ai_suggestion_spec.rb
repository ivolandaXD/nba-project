# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlacedAiSuggestion, type: :model do
  let(:user) { create(:user) }
  let(:game) { create(:game, home_team: 'LAL', away_team: 'BOS', game_date: Date.current) }
  let(:player) { create(:player, name: 'Callback Roster', team: 'LAL', nba_player_id: 999_010) }

  before { allow(Nba::Season).to receive(:current).and_return('2025-26') }

  it 'resyncs legs only when legs or game_id change (not on evaluation_note alone)' do
    placed =
      create(
        :placed_ai_suggestion,
        user: user,
        game: game,
        slip_kind: 'parlay',
        legs: [
          { 'player' => player.name, 'market' => 'PTS', 'line' => '10.5' }
        ]
      )

    expect(placed.placed_ai_suggestion_legs.count).to eq(1)
    first_leg_id = placed.placed_ai_suggestion_legs.first.id

    placed.update!(evaluation_note: 'só nota')
    placed.reload
    expect(placed.placed_ai_suggestion_legs.first.id).to eq(first_leg_id)

    placed.update!(
      legs: [
        { 'player' => player.name, 'market' => 'PTS', 'line' => '10.5' },
        { 'player' => player.name, 'market' => 'REB', 'line' => '5.5' }
      ]
    )
    placed.reload
    expect(placed.placed_ai_suggestion_legs.count).to eq(2)
  end
end
