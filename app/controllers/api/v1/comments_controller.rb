module Api
  module V1
    class CommentsController < BaseController
      def index
        authorize Comment
        game_id = params.require(:game_id)
        comments = policy_scope(Comment).where(game_id: game_id).includes(:user).order(created_at: :desc)
        render json: comments.as_json(
          only: %i[id game_id content created_at],
          include: { user: { only: %i[id email] } }
        )
      end

      def create
        authorize Comment
        comment = current_user.comments.build(comment_params)
        if comment.save
          render json: comment.as_json(only: %i[id user_id game_id content created_at]), status: :created
        else
          render json: { errors: comment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def comment_params
        params.require(:comment).permit(:game_id, :content)
      end
    end
  end
end
