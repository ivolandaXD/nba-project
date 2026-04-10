module PlayerMetrics
  class Calculator
    STAT_COLUMNS = {
      points: :points,
      rebounds: :rebounds,
      assists: :assists,
      steals: :steals,
      blocks: :blocks,
      threes: :three_pt_made,
      turnovers: :turnovers
    }.freeze

    CACHE_TTL = 15.minutes

    def self.cached_payload(player, stat_key: :points, line: nil, opponent_team: nil)
      calc = new(player, stat_key: stat_key, line: line, opponent_team: opponent_team)
      Rails.cache.fetch(calc.cache_key, expires_in: CACHE_TTL) do
        {
          for_ai: calc.to_analysis_input(line: line, odds: nil),
          scorer_inputs: calc.scorer_input_hash
        }
      end
    end

    def initialize(player, stat_key: :points, line: nil, opponent_team: nil)
      @player = player
      @stat_key = stat_key.to_sym
      @line = line
      @opponent_team = opponent_team
      @column = STAT_COLUMNS.fetch(@stat_key, :points)
      @scope = @player.player_game_stats
    end

    def cache_key
      stamp = @player.player_game_stats.maximum(:updated_at)&.to_i || 0
      ['player_metrics/v3', @player.id, stamp, @stat_key, @line.to_s, @opponent_team.to_s.downcase].join('/')
    end

    def season_avg
      avg(@scope)
    end

    def last_10_avg
      avg(@scope.order(game_date: :desc).limit(10))
    end

    def vs_opponent_avg
      return nil if @opponent_team.blank?

      avg(@scope.where('LOWER(opponent_team) = ?', @opponent_team.to_s.downcase))
    end

    def variance
      values = numeric_values
      return nil if values.size < 2

      mean = values.sum / values.size
      values.sum { |v| (v - mean)**2 } / (values.size - 1)
    end

    def variance_rounded
      v = variance
      v&.round(2)
    end

    def std_dev
      v = variance
      return nil if v.nil?

      Math.sqrt(v).round(2)
    end

    def coefficient_of_variation
      m = season_avg
      return nil if m.nil? || m.to_f.abs < 0.01

      sd = std_dev
      return nil if sd.nil?

      (sd / m.to_f).round(3)
    end

    def pct_games_above(threshold)
      return nil unless @stat_key == :points

      scoped = @scope.where.not(@column => nil)
      total = scoped.count
      return nil if total.zero?

      (100.0 * scoped.where("#{@column} > ?", threshold.to_f).count / total).round(1)
    end

    def streak_status
      baseline = season_avg
      return 'neutral' if baseline.nil?

      rows = @scope.where.not(@column => nil).order(game_date: :desc).limit(12).pluck(@column)
      return 'neutral' if rows.size < 3

      first_above = rows[0].to_f > baseline
      count = 0
      rows.each do |val|
        above = val.to_f > baseline
        break if above != first_above

        count += 1
      end
      return 'hot' if count >= 3 && first_above
      return 'cold' if count >= 3 && !first_above

      'neutral'
    end

    def minutes_avg
      v = @scope.average(:minutes)
      v&.to_f&.round(2)
    end

    def points_per_minute
      ma = minutes_avg
      pa = season_avg
      return nil if ma.nil? || ma.to_f <= 0 || pa.nil?

      (pa.to_f / ma.to_f).round(3)
    end

    def usage_rate
      pairs = @scope.where.not(fga: nil).where.not(fta: nil).pluck(:fga, :fta)
      return nil if pairs.empty?

      (pairs.sum { |fga, fta| fga.to_i + fta.to_i }.to_f / pairs.size).round(2)
    end

    def over_line_rate
      return nil if @line.nil?

      scoped = @scope.where.not(@column => nil)
      total = scoped.count
      return nil if total.zero?

      over = scoped.where("#{@column} > ?", @line.to_f).count
      (100.0 * over / total).round(1)
    end

    def trend_last_10
      s = season_avg
      l = last_10_avg
      return nil if s.nil? || l.nil?

      (l - s).round(2)
    end

    def home_avg
      avg(@scope.where(is_home: true))
    end

    def away_avg
      avg(@scope.where(is_home: false))
    end

    def scorer_input_hash
      {
        coefficient_of_variation: coefficient_of_variation,
        trend_last_10: trend_last_10,
        over_line_rate: over_line_rate,
        over_20_rate: pct_games_above(20),
        streak_status: streak_status,
        line: @line
      }
    end

    def to_analysis_input(line: @line, odds: nil)
      h = {
        player: { id: @player.id, name: @player.name, team: @player.team },
        stat: @stat_key.to_s,
        season_avg: season_avg,
        last_10_avg: last_10_avg,
        vs_opponent_avg: vs_opponent_avg,
        std_dev: std_dev,
        variance: variance_rounded,
        coefficient_of_variation: coefficient_of_variation,
        over_15_rate: pct_games_above(15),
        over_20_rate: pct_games_above(20),
        over_25_rate: pct_games_above(25),
        streak_status: streak_status,
        trend: trend_last_10,
        home_avg: home_avg,
        away_avg: away_avg,
        minutes_avg: minutes_avg,
        points_per_minute: points_per_minute,
        usage_rate: usage_rate,
        over_line_rate: over_line_rate,
        line: line,
        odds: odds
      }
      h.compact
    end

    private

    def numeric_values
      @scope.pluck(@column).compact.map(&:to_f)
    end

    def avg(relation)
      v = relation.average(@column)
      v&.to_f&.round(2)
    end
  end
end
