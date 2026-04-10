module Api
  module V1
    class AlertsController < BaseController
      def index
        authorize Alert
        alerts = policy_scope(Alert).includes(:player).order(created_at: :desc)
        render json: alerts.as_json(
          only: %i[id player_id condition_type threshold is_active created_at],
          include: { player: { only: %i[id name team] } }
        )
      end

      def create
        authorize Alert
        alert = current_user.alerts.build(alert_params)
        if alert.save
          render json: alert.as_json(only: %i[id user_id player_id condition_type threshold is_active created_at]), status: :created
        else
          render json: { errors: alert.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        alert = policy_scope(Alert).find(params[:id])
        authorize alert
        if alert.update(alert_update_params)
          render json: alert.as_json(only: %i[id user_id player_id condition_type threshold is_active updated_at])
        else
          render json: { errors: alert.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def alert_params
        params.require(:alert).permit(:player_id, :condition_type, :threshold, :is_active)
      end

      def alert_update_params
        params.require(:alert).permit(:is_active, :threshold, :condition_type)
      end
    end
  end
end
