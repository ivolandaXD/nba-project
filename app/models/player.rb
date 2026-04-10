class Player < ApplicationRecord
  has_many :player_game_stats, dependent: :destroy
  has_many :games, through: :player_game_stats
  has_many :odds_snapshots, dependent: :destroy
  has_many :ai_predictions, dependent: :destroy
  has_many :bets, dependent: :destroy
  has_many :alerts, dependent: :destroy

  validates :name, presence: true
  validates :nba_player_id, uniqueness: true, allow_nil: true
end
