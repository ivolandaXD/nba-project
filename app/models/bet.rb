class Bet < ApplicationRecord
  RESULTS = %w[win loss pending].freeze
  BET_TYPES = %w[points rebounds assists steals blocks threes turnovers].freeze

  belongs_to :user
  belongs_to :game
  belongs_to :player

  validates :bet_type, presence: true, inclusion: { in: BET_TYPES }
  validates :result, inclusion: { in: RESULTS }
end
