# frozen_string_literal: true

class GameRoster
  def self.normalize_abbr(raw)
    s = raw.to_s.strip
    return nil if s.blank?

    NbaStats::OpponentInferrer.canonical_abbr(s).presence || s.upcase
  end

  def initialize(game:, season: Nba::Season.current)
    @game = game
    @season = season.to_s.strip
    @home_abbr = self.class.normalize_abbr(game.home_team)
    @away_abbr = self.class.normalize_abbr(game.away_team)
  end

  attr_reader :home_abbr, :away_abbr

  def home_players
    roster_for_abbr(@home_abbr)
  end

  def away_players
    roster_for_abbr(@away_abbr)
  end

  # Jogadores únicos dos dois times, ordenados por nome (útil em selects e props).
  def all_players
    (home_players.to_a + away_players.to_a).uniq.sort_by { |p| p.name.to_s.downcase }
  end

  private

  def roster_for_abbr(abbr)
    return Player.none if abbr.blank?

    rel = Player.where('UPPER(TRIM(team)) = ?', abbr).order(:name)
    return rel if rel.exists?

    ids =
      Player.joins(:player_season_stats)
            .where(player_season_stats: { season: @season, team_abbr: abbr })
            .distinct
            .pluck(:id)

    return Player.none if ids.blank?

    Player.where(id: ids).order(:name)
  end
end
