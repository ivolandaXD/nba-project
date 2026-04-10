module Api
  module V1
    module Nba
      class GamePlayersController < BaseController
        def index
          game = Game.find(params[:game_id])
          authorize game, :show?

          players = Player.joins(:player_game_stats)
                          .where(player_game_stats: { game_id: game.id })
                          .distinct
                          .includes(:player_game_stats)
          render json: players.as_json(
            only: %i[id name team nba_player_id],
            include: { player_game_stats: { only: :game_id } }
          )
        end
      end
    end
  end
end
