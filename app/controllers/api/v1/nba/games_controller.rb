module Api
  module V1
    module Nba
      class GamesController < BaseController
        def index
          authorize Game
          games = policy_scope(Game).order(game_date: :desc)
          render json: games.as_json(only: %i[id game_date home_team away_team status nba_game_id created_at])
        end

        def show
          game = Game.find(params[:id])
          authorize game
          render json: game.as_json(only: %i[id game_date home_team away_team status nba_game_id created_at])
        end

        def fetch_odds
          game = Game.find(params[:id])
          authorize game, :fetch_odds?
          result = ::Odds::GameOddsImporter.call(game)
          if result.success?
            render json: { snapshots_created: result.snapshots_count }
          else
            render json: { error: result.error }, status: :unprocessable_entity
          end
        end

        def analyze
          game = Game.find(params[:id])
          authorize game, :analyze?

          player = Player.find(params.require(:player_id))
          result = ::Ai::GamePlayerAnalysis.call(
            game: game,
            player: player,
            line: params[:line],
            bet_type: params[:bet_type].presence || 'points',
            odds: params[:odds],
            confidence_score: params[:confidence_score]
          )

          unless result[:ok]
            render json: { error: result[:error] }, status: :unprocessable_entity
            return
          end

          render json: result[:prediction].as_json(only: %i[id game_id player_id input_data output_text confidence_score created_at])
        end
      end
    end
  end
end
