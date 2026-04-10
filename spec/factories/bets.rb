FactoryBot.define do
  factory :bet do
    user { nil }
    game { nil }
    player { nil }
    bet_type { "MyString" }
    line { "9.99" }
    odds { "MyString" }
    result { "MyString" }
  end
end
