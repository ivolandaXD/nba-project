module Web
  class DashboardController < Web::ApplicationController
    def index
      @games = Game.where(game_date: Time.zone.today).order(:nba_game_id)
    end

    def sync_games
      today = Time.zone.today
      result = NbaStats::ScoreboardSync.call(date: today)
      if result.success?
        flash[:notice] =
          "#{result.games_count} jogo(s) de hoje (#{today.strftime('%d/%m/%Y')}) sincronizados com a NBA. " \
          'Apenas esta data é buscada no scoreboard.'
      else
        flash[:alert] = result.error
      end
      redirect_to root_path
    end
  end
end
