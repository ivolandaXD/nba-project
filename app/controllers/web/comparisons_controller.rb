module Web
  class ComparisonsController < Web::ApplicationController
    def index
      authorize :comparison, :index?
    end

    def teams
      authorize :comparison, :teams?

      @season = Nba::Season.current
      @team_a = params[:team_a].to_s.upcase.presence
      @team_b = params[:team_b].to_s.upcase.presence
      @teams = NbaStats::TeamCodes::ALL

      return unless @team_a.present? && @team_b.present? && @team_a != @team_b

      @roster_a = roster_snapshot(@team_a, @season)
      @roster_b = roster_snapshot(@team_b, @season)
      @h2h_games = head_to_head_games(@team_a, @team_b)
    end

    def matchup
      authorize :comparison, :matchup?

      @season = Nba::Season.current
      @players = Player.where.not(nba_player_id: nil).order(:name)
      @teams = NbaStats::TeamCodes::ALL
      @player = Player.find_by(id: params[:player_id])
      @opponent = params[:opponent].to_s.upcase.presence

      return unless @player && @opponent

      @opponent_stats = @player.player_game_stats
                                .where('LOWER(opponent_team) = ?', @opponent.downcase)
                                .order(game_date: :desc)
      @metrics_pts = PlayerMetrics::Calculator.new(@player, stat_key: :points, opponent_team: @opponent)
      @metrics_reb = PlayerMetrics::Calculator.new(@player, stat_key: :rebounds, opponent_team: @opponent)
      @metrics_ast = PlayerMetrics::Calculator.new(@player, stat_key: :assists, opponent_team: @opponent)

      @team_vs_opponent_games = games_between_teams(@player.team.to_s.upcase, @opponent)
    end

    private

    def roster_snapshot(abbr, season)
      ids = Player.where('UPPER(TRIM(team)) = ?', abbr).where.not(nba_player_id: nil).pluck(:id)
      PlayerSeasonStat.includes(:player).where(season: season, player_id: ids).order('players.name')
    end

    def head_to_head_games(a, b)
      Game.where(
        '(UPPER(home_team) = ? AND UPPER(away_team) = ?) OR (UPPER(home_team) = ? AND UPPER(away_team) = ?)',
        a, b, b, a
      ).order(game_date: :desc)
    end

    def games_between_teams(team_abbr, opp_abbr)
      return Game.none if team_abbr.blank? || opp_abbr.blank?

      head_to_head_games(team_abbr, opp_abbr)
    end
  end
end
