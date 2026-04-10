class PlayerOpponentSplit < ApplicationRecord
  belongs_to :player

  validates :season, :opponent_team, presence: true
  validates :player_id, uniqueness: { scope: %i[opponent_team season] }
end
