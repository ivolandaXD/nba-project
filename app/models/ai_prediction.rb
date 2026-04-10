class AiPrediction < ApplicationRecord
  belongs_to :game
  belongs_to :player

  validates :output_text, presence: true
end
