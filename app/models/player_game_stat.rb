class PlayerGameStat < ApplicationRecord
  belongs_to :player
  belongs_to :game

  validates :player_id, uniqueness: { scope: :game_id }
end
