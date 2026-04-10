module Web
  class RankingController < Web::ApplicationController
    def index
      authorize :ranking, :index?
      @rows = Ranking::Leaderboard.rows
    end
  end
end
