FactoryBot.define do
  factory :alert do
    user { nil }
    player { nil }
    condition_type { "MyString" }
    threshold { "9.99" }
    is_active { false }
  end
end
