class Game < ApplicationRecord
  has_many :player_game_stats, dependent: :destroy
  has_many :players, -> { distinct }, through: :player_game_stats
  has_many :odds_snapshots, dependent: :destroy
  has_many :ai_predictions, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :bets, dependent: :destroy

  validates :home_team, :away_team, presence: true

  # meta: jsonb — blocos opcionais (ex.: espn.odds) para IA e debug sem novas colunas a cada campo da API.

  # Soma PTS do box importado (`player_game_stats` × `players.team`), alinhando abrevs (GS/GSW, etc.).
  # @return [Array(Integer, Integer), nil] [pontos_casa, pontos_visitante] ou nil se não houver dados cruzáveis
  def box_score_home_away_points
    return @box_score_home_away_points if defined?(@box_score_home_away_points)

    sums =
      player_game_stats
      .joins(:player)
      .where.not(players: { team: [nil, ''] })
      .group(Arel.sql("UPPER(TRIM(players.team))"))
      .sum(:points)

    return @box_score_home_away_points = nil if sums.blank?

    hp = team_points_for_abbr(sums, home_team)
    ap = team_points_for_abbr(sums, away_team)
    return @box_score_home_away_points = nil if hp.to_i <= 0 || ap.to_i <= 0

    @box_score_home_away_points = [hp.to_i, ap.to_i]
  end

  private

  def team_points_for_abbr(sums_by_team, abbr)
    target = NbaStats::OpponentInferrer.canonical_abbr(abbr)
    return 0 if target.blank?

    sums_by_team.sum do |(raw_team, pts)|
      NbaStats::OpponentInferrer.canonical_abbr(raw_team) == target ? pts.to_i : 0
    end
  end
end
