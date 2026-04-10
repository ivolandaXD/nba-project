module Api
  module V1
    class BetsController < BaseController
      def index
        authorize Bet
        bets = policy_scope(Bet).includes(:game, :player).order(created_at: :desc)
        render json: bets.as_json(
          only: %i[id game_id player_id bet_type line odds result created_at],
          include: {
            game: { only: %i[id game_date home_team away_team] },
            player: { only: %i[id name team] }
          }
        )
      end

      def create
        authorize Bet
        bet = current_user.bets.build(bet_params)
        if bet.save
          render json: bet.as_json(only: %i[id user_id game_id player_id bet_type line odds result created_at]), status: :created
        else
          render json: { errors: bet.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def bet_params
        params.require(:bet).permit(:game_id, :player_id, :bet_type, :line, :odds)
      end
    end
  end
end
