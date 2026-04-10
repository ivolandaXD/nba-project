class Player < ApplicationRecord
  has_many :player_game_stats, dependent: :destroy
  has_many :player_season_stats, dependent: :destroy
  has_many :player_opponent_splits, dependent: :destroy
  has_many :games, through: :player_game_stats
  has_many :odds_snapshots, dependent: :destroy
  has_many :ai_predictions, dependent: :destroy
  has_many :bets, dependent: :destroy
  has_many :alerts, dependent: :destroy

  validates :name, presence: true
  validates :nba_player_id, uniqueness: true, allow_nil: true
  validates :bdl_player_id, uniqueness: true, allow_nil: true

  def opponent_split_for(season:, opponent_abbr:)
    return if opponent_abbr.blank?

    player_opponent_splits.find_by(season: season.to_s.strip, opponent_team: opponent_abbr.to_s.strip.upcase)
  end
end
