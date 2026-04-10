module Web
  class BetsController < Web::ApplicationController
    def create
      @game = Game.find(params[:game_id])
      authorize @game, :show?

      @bet = current_user.bets.build(bet_params.merge(game: @game))
      authorize @bet

      if @bet.save
        flash[:notice] = 'Aposta registrada.'
      else
        flash[:alert] = @bet.errors.full_messages.to_sentence
      end
      redirect_to game_path(@game)
    end

    def update
      @game = Game.find(params[:game_id])
      @bet = @game.bets.find(params[:id])
      authorize @bet

      @bet.assign_attributes(bet_update_params)
      @bet.apply_points_over_result if @bet.points_prop? && @bet.line.present? && @bet.final_stat_value.present?

      if @bet.save
        flash[:notice] = 'Aposta atualizada.'
      else
        flash[:alert] = @bet.errors.full_messages.to_sentence
      end
      redirect_to game_path(@game)
    end

    private

    def bet_params
      params.require(:bet).permit(:player_id, :bet_type, :line, :odds)
    end

    def bet_update_params
      params.require(:bet).permit(:final_stat_value, :result)
    end
  end
end
