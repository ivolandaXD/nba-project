module Api
  module V1
    module Nba
      class PlayersController < BaseController
        def fetch_game_logs
          player = Player.find(params[:id])
          authorize player, :fetch_game_logs?

          season = params[:season].presence || Nba::Season.current
          result = ::NbaStats::PlayerGameLogImporter.call(player, season: season)
          if result.success?
            render json: { imported_rows: result.stats_count, season: season }
          else
            render json: { error: result.error }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
