FactoryBot.define do
  factory :odds_snapshot do
    game { nil }
    player { nil }
    market_type { "MyString" }
    line { "9.99" }
    odds { "MyString" }
    source { "MyString" }
  end
end
