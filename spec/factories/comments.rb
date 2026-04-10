FactoryBot.define do
  factory :comment do
    user { nil }
    game { nil }
    content { "MyText" }
  end
end
