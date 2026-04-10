module Bets
  # Métricas de acerto para player props (apostas com result win/loss).
  class Performance
    def self.overall
      settled = Bet.where(result: %w[win loss])
      total = settled.count
      return { total: 0, wins: 0, hit_rate_percent: nil } if total.zero?

      wins = settled.where(result: 'win').count
      { total: total, wins: wins, hit_rate_percent: (100.0 * wins / total).round(1) }
    end

    def self.for_user(user)
      settled = Bet.where(user: user, result: %w[win loss])
      total = settled.count
      return { total: 0, wins: 0, hit_rate_percent: nil } if total.zero?

      wins = settled.where(result: 'win').count
      { total: total, wins: wins, hit_rate_percent: (100.0 * wins / total).round(1) }
    end

    def self.for_player(player_id)
      settled = Bet.where(player_id: player_id, result: %w[win loss])
      total = settled.count
      return { total: 0, wins: 0, hit_rate_percent: nil } if total.zero?

      wins = settled.where(result: 'win').count
      { total: total, wins: wins, hit_rate_percent: (100.0 * wins / total).round(1) }
    end

    def self.points_props_overall
      settled = Bet.where(bet_type: 'points', result: %w[win loss])
      total = settled.count
      return { total: 0, wins: 0, hit_rate_percent: nil } if total.zero?

      wins = settled.where(result: 'win').count
      { total: total, wins: wins, hit_rate_percent: (100.0 * wins / total).round(1) }
    end

    def self.for_user_points_props(user)
      settled = Bet.where(user: user, bet_type: 'points', result: %w[win loss])
      total = settled.count
      return { total: 0, wins: 0, hit_rate_percent: nil } if total.zero?

      wins = settled.where(result: 'win').count
      { total: total, wins: wins, hit_rate_percent: (100.0 * wins / total).round(1) }
    end

    # Agrupa por faixa de linha (arredondada) para props de pontos.
    def self.by_line_bucket(bet_type: 'points', decimals: 1)
      settled = Bet.where(bet_type: bet_type, result: %w[win loss]).where.not(line: nil)
      groups = settled.group_by { |b| b.line.to_f.round(decimals) }

      groups.map do |bucket, rows|
        wins = rows.count { |b| b.result == 'win' }
        total = rows.size
        {
          line_bucket: bucket,
          total: total,
          wins: wins,
          hit_rate_percent: total.positive? ? (100.0 * wins / total).round(1) : nil
        }
      end.sort_by { |h| h[:line_bucket] }
    end

    # Taxa por jogador (props de pontos), apenas quem tem volume mínimo.
    def self.top_points_props_players(min_bets: 3, limit: 10)
      settled = Bet.where(bet_type: 'points', result: %w[win loss])
      tally = Hash.new { |h, pid| h[pid] = { total: 0, wins: 0 } }
      settled.pluck(:player_id, :result).each do |pid, res|
        t = tally[pid]
        t[:total] += 1
        t[:wins] += 1 if res == 'win'
      end

      tally
        .select { |_pid, v| v[:total] >= min_bets }
        .map do |pid, v|
          {
            player_id: pid,
            total: v[:total],
            wins: v[:wins],
            hit_rate_percent: (100.0 * v[:wins] / v[:total]).round(1)
          }
        end
        .sort_by { |r| [-r[:hit_rate_percent], -r[:total]] }
        .first(limit)
    end
  end
end
