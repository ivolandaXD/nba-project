module Ranking
  class Leaderboard
    def self.rows
      aggregates = Bet.where(result: %w[win loss])
                      .group(:user_id)
                      .select(
                        :user_id,
                        'COUNT(*) AS total_bets',
                        "SUM(CASE WHEN result = 'win' THEN 1 ELSE 0 END) AS wins"
                      )

      user_ids = aggregates.map(&:user_id)
      users_by_id = User.where(id: user_ids).index_by(&:id)

      data = aggregates.map do |row|
        total = row.total_bets.to_i
        wins = row.read_attribute('wins').to_i
        rate = total.positive? ? (100.0 * wins / total).round(1) : 0.0
        u = users_by_id[row.user_id]
        {
          user_id: row.user_id,
          email: u&.email,
          total_bets: total,
          wins: wins,
          hit_rate_percent: rate
        }
      end

      data.sort_by { |h| [-h[:hit_rate_percent], -h[:total_bets]] }
    end
  end
end
