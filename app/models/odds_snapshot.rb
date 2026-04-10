class OddsSnapshot < ApplicationRecord
  belongs_to :game
  belongs_to :player, optional: true

  validates :market_type, :source, presence: true
end
