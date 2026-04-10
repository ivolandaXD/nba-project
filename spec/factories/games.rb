FactoryBot.define do
  factory :game do
    game_date { Date.current }
    home_team { 'LAL' }
    away_team { 'BOS' }
    status { 'scheduled' }
  end
end
