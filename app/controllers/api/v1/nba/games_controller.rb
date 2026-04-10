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

          safe = ::PlayerProps::ManualContext.permit_params(
            params,
            :player_id, :line, :bet_type, :odds, :confidence_score, :user_note
          )
          player = Player.find(safe.require(:player_id))
          note = safe[:user_note].to_s.strip
          note = note[0, 2000] if note.length > 2000

          result = ::Ai::GamePlayerAnalysis.call(
            game: game,
            player: player,
            line: safe[:line],
            bet_type: safe[:bet_type].presence || 'points',
            odds: safe[:odds],
            confidence_score: safe[:confidence_score],
            user_note: note.presence,
            params: safe
          )

          unless result[:ok]
            render json: { error: result[:error] }, status: :unprocessable_entity
            return
          end

          pred = result[:prediction]
          render json: pred.as_json(only: %i[id game_id player_id input_data output_text confidence_score created_at])
            .merge('analysis_meta' => pred.analysis_meta)
        end
      end
    end
  end
end
