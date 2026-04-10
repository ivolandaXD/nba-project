module Web
  class PlayerAlertsController < Web::ApplicationController
    def create
      @player = Player.find(params[:player_id])
      authorize @player, :show?

      @alert = current_user.alerts.build(alert_params.merge(player: @player))
      authorize @alert

      if @alert.save
        flash[:notice] = 'Alerta criado.'
      else
        flash[:alert] = @alert.errors.full_messages.to_sentence
      end
      redirect_to player_path(@player)
    end

    private

    def alert_params
      params.require(:alert).permit(:condition_type, :threshold)
    end
  end
end
