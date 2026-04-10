module Api
  module V1
    class RankingController < BaseController
      def index
        authorize :ranking, :index?

        render json: { ranking: Ranking::Leaderboard.rows }
      end
    end
  end
end
