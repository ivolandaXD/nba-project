class Game < ApplicationRecord
  has_many :player_game_stats, dependent: :destroy
  has_many :players, -> { distinct }, through: :player_game_stats
  has_many :odds_snapshots, dependent: :destroy
  has_many :ai_predictions, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :bets, dependent: :destroy

  validates :home_team, :away_team, presence: true

  # meta: jsonb — blocos opcionais (ex.: espn.odds) para IA e debug sem novas colunas a cada campo da API.
end
