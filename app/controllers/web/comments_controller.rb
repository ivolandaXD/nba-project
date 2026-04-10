module Web
  class CommentsController < Web::ApplicationController
    def create
      @game = Game.find(params[:game_id])
      authorize @game, :show?

      @comment = current_user.comments.build(comment_params.merge(game: @game))
      authorize @comment

      if @comment.save
        flash[:notice] = 'Comentário publicado.'
      else
        flash[:alert] = @comment.errors.full_messages.to_sentence
      end
      redirect_to game_path(@game)
    end

    private

    def comment_params
      params.require(:comment).permit(:content)
    end
  end
end
