FactoryBot.define do
  factory :player_game_stat do
    player
    game
    game_date { game.game_date }
    opponent_team { 'BOS' }
    is_home { true }
    minutes { 32.5 }
    points { 20 }
    assists { 5 }
    rebounds { 7 }
    steals { 1 }
    blocks { 0 }
    turnovers { 2 }
    fgm { 8 }
    fga { 16 }
    fg_pct { 0.5 }
    three_pt_made { 2 }
    three_pt_attempted { 6 }
    three_pt_pct { 0.333 }
    ftm { 2 }
    fta { 2 }
    ft_pct { 1.0 }
  end
end
