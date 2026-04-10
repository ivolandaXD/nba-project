class PlayerSeasonStat < ApplicationRecord
  belongs_to :player

  validates :season, presence: true
  validates :player_id, uniqueness: { scope: :season }
end
