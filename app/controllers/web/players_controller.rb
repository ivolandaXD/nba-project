module Web
  class PlayersController < Web::ApplicationController
    def show
      @player = Player.find(params[:id])
      authorize @player, :show?
      @my_alerts = current_user.alerts.where(player_id: @player.id).order(created_at: :desc)
    end
  end
end
