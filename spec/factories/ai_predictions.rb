FactoryBot.define do
  factory :ai_prediction do
    game { nil }
    player { nil }
    input_data { "" }
    output_text { "MyText" }
    confidence_score { "9.99" }
  end
end
