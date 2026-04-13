# frozen_string_literal: true

FactoryBot.define do
  factory :placed_ai_suggestion do
    user
    game { nil }
    sequence(:external_bet_id) { |n| "factory-bet-#{n}" }
    slip_kind { 'single' }
    description { 'Aposta de teste' }
    legs { [{ 'player' => 'Test Player', 'market' => 'Total de pontos', 'line' => '10.5' }] }
    result { 'pending' }
  end
end
