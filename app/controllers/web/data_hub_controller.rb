# frozen_string_literal: true

module Web
  class DataHubController < Web::ApplicationController
    COUNT_LABELS = [
      [:players, 'Jogadores (total)'],
      [:players_nba_id, 'Jogadores com NBA ID'],
      [:players_bdl_id, 'Jogadores com BallDontLie ID'],
      [:games, 'Jogos'],
      [:player_game_stats, 'Linhas em player_game_stats'],
      [:player_season_stats, 'Linhas em player_season_stats'],
      [:team_season_stats, 'Linhas em team_season_stats (temporada)'],
      [:team_season_with_pace, 'Times com pace preenchido'],
      [:opponent_splits, 'Splits jogador × adversário'],
      [:ai_predictions, 'Previsões IA'],
      [:odds_snapshots, 'Snapshots de odds']
    ].freeze

    def index
      authorize DataHub, :index?

      @season = Nba::Season.current
      counts = build_counts(@season)
      @count_rows = COUNT_LABELS.map { |key, label| { label: label, value: counts[key] } }
      @pgs_by_source = PlayerGameStat.group(:data_source).count
      @pss_by_source = PlayerSeasonStat.group(:data_source).count
      @sample_teams = TeamSeasonStat.where(season: @season).order(Arel.sql('pts DESC NULLS LAST')).limit(20)
    end

    private

    def build_counts(season)
      {
        players: Player.count,
        players_nba_id: Player.where.not(nba_player_id: nil).count,
        players_bdl_id: Player.where.not(bdl_player_id: nil).count,
        games: Game.count,
        player_game_stats: PlayerGameStat.count,
        player_season_stats: PlayerSeasonStat.count,
        team_season_stats: TeamSeasonStat.where(season: season).count,
        team_season_with_pace: TeamSeasonStat.where(season: season).where.not(pace: nil).count,
        opponent_splits: PlayerOpponentSplit.where(season: season).count,
        ai_predictions: AiPrediction.count,
        odds_snapshots: OddsSnapshot.count
      }
    end
  end
end
