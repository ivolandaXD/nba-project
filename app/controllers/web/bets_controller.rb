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

    private

    def bet_params
      params.require(:bet).permit(:player_id, :bet_type, :line, :odds)
    end
  end
end
