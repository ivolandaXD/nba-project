module Web
  class RankingController < Web::ApplicationController
    def index
      authorize :ranking, :index?
      @rows = Ranking::Leaderboard.rows
      @props_overall = Bets::Performance.points_props_overall
      @props_mine = Bets::Performance.for_user_points_props(current_user)
      @props_by_line = Bets::Performance.by_line_bucket
      @props_top_players = Bets::Performance.top_points_props_players
      top_ids = @props_top_players.map { |r| r[:player_id] }
      @props_top_players_by_id = Player.where(id: top_ids).index_by(&:id)
    end
  end
end
