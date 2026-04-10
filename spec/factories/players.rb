FactoryBot.define do
  factory :player do
    sequence(:name) { |n| "Player #{n}" }
    team { 'LAL' }
    nba_player_id { nil }
  end
end
