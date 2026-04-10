module Web
  class DashboardController < Web::ApplicationController
    def index
      @scoreboard_date = NbaStats::Calendar.scoreboard_today
      @games = Game.where(game_date: @scoreboard_date).order(:nba_game_id)
    end

    def sync_games
      today = NbaStats::Calendar.scoreboard_today
      result = scoreboard_sync_for(today)
      if result.success?
        source = scoreboard_source_label
        flash[:notice] =
          if result.games_count.zero?
            "Nenhum jogo na grade para #{today.strftime('%d/%m/%Y')} (ET) (#{source}). " \
              'Confira se há jogos nessa data (fora de temporada / feriado) ou tente outro dia.'
          else
            "#{result.games_count} jogo(s) para #{today.strftime('%d/%m/%Y')} (ET) via #{source}. " \
              'Só essa data é buscada.'
          end
      else
        flash[:alert] = result.error
      end
      redirect_to root_path
    end

    private

    def scoreboard_sync_for(today)
      case ENV.fetch('NBA_SCOREBOARD_PROVIDER', 'espn').to_s.strip.downcase
      when 'nba_stats', 'nba', 'stats_nba'
        NbaStats::ScoreboardSync.call(date: today)
      else
        Espn::ScoreboardSync.call(date: today)
      end
    end

    def scoreboard_source_label
      case ENV.fetch('NBA_SCOREBOARD_PROVIDER', 'espn').to_s.strip.downcase
      when 'nba_stats', 'nba', 'stats_nba'
        'stats.nba.com'
      else
        'ESPN'
      end
    end
  end
end
