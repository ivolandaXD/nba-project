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
      ['player_metrics/v5', @player.id, stamp, @stat_key, @line.to_s, @opponent_team.to_s.downcase].join('/')
    end

    def season_avg
      avg(@scope)
    end

    def last_5_avg
      avg(ordered_games_scope.limit(5))
    end

    def last_10_avg
      avg(ordered_games_scope.limit(10))
    end

    def vs_opponent_avg
      return nil if @opponent_team.blank?

      avg(@scope.where('UPPER(TRIM(opponent_team)) = ?', @opponent_team.to_s.strip.upcase))
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

    def fga_avg
      v = @scope.where.not(fga: nil).average(:fga)
      v&.to_f&.round(2)
    end

    def fta_avg
      v = @scope.where.not(fta: nil).average(:fta)
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

    # Proxy de uso por minuto: (FGA + 0.44*FTA + TOV) / MIN por jogo, média.
    def usage_rate_per_minute
      rel = @scope.where.not(minutes: nil).where('minutes > 0')
      return nil unless rel.exists?

      total = 0.0
      n = 0
      rel.pluck(:fga, :fta, :turnovers, :minutes).each do |fga, fta, tov, min|
        m = min.to_f
        next if m <= 0

        fga_i = fga.to_i
        fta_i = fta.to_i
        tov_i = tov.to_i
        total += (fga_i + 0.44 * fta_i + tov_i) / m
        n += 1
      end
      return nil if n.zero?

      (total / n).round(3)
    end

    def team_pace
      abbr = @player.team.to_s.strip.upcase
      return nil if abbr.blank?

      TeamSeasonStat.find_by(season: Nba::Season.current, team_abbr: abbr)&.pace&.to_f&.round(3)
    end

    def league_avg_pace
      v = TeamSeasonStat.where(season: Nba::Season.current).where.not(pace: nil).average(:pace)
      v&.to_f&.round(3)
    end

    def pace_factor
      tp = team_pace
      lp = league_avg_pace
      return nil if tp.blank? || lp.blank? || lp <= 0

      (tp / lp).round(3)
    end

    # Projeção de pontos amortecida pelo ritmo do time vs liga (exponent < 1).
    def season_avg_points_pace_adjusted
      return nil unless @stat_key == :points

      base = season_avg
      pf = pace_factor
      return nil if base.nil? || pf.nil?

      exp = ENV.fetch('PLAYER_METRICS_PACE_EXPONENT', '0.35').to_f
      (base.to_f * (pf.to_f**exp)).round(2)
    end

    def over_line_rate
      return nil if @line.nil?

      scoped = @scope.where.not(@column => nil)
      total = scoped.count
      return nil if total.zero?

      over = scoped.where("#{@column} > ?", @line.to_f).count
      (100.0 * over / total).round(1)
    end

    # Tendência principal (player props pontos): últimos 5 − média temporada.
    def trend_last_5
      s = season_avg
      l = last_5_avg
      return nil if s.nil? || l.nil?

      (l - s).round(2)
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
        trend_last_5: trend_last_5,
        trend_last_10: trend_last_10,
        over_line_rate: over_line_rate,
        over_20_rate: pct_games_above(20),
        last_5_avg: last_5_avg,
        season_avg: season_avg,
        streak_status: streak_status,
        line: @line
      }
    end

    def to_analysis_input(line: @line, odds: nil)
      return legacy_non_points_input(line: line, odds: odds) unless @stat_key == :points

      points_props_input(line: line, odds: odds)
    end

    private

    def ordered_games_scope
      @scope.where.not(@column => nil).order(game_date: :desc)
    end

    def numeric_values
      @scope.pluck(@column).compact.map(&:to_f)
    end

    def avg(relation)
      v = relation.average(@column)
      v&.to_f&.round(2)
    end

    def points_props_input(line:, odds:)
      {
        player: { id: @player.id, name: @player.name, team: @player.team },
        stat: 'points',
        line: line,
        odds: odds,
        season_avg_points: season_avg,
        last_5_avg_points: last_5_avg,
        last_10_avg_points: last_10_avg,
        vs_opponent_avg_points: vs_opponent_avg,
        std_dev_points: std_dev,
        variance_points: variance_rounded,
        coefficient_of_variation: coefficient_of_variation,
        over_15_rate: pct_games_above(15),
        over_20_rate: pct_games_above(20),
        over_25_rate: pct_games_above(25),
        over_line_rate: over_line_rate,
        trend: trend_last_5,
        trend_last_10_vs_season: trend_last_10,
        minutes_avg: minutes_avg,
        fga_avg: fga_avg,
        fta_avg: fta_avg,
        home_avg_points: home_avg,
        away_avg_points: away_avg,
        streak_status: streak_status,
        points_per_minute: points_per_minute,
        usage_fga_fta_avg: usage_rate,
        usage_rate_per_minute: usage_rate_per_minute,
        team_pace: team_pace,
        league_avg_pace: league_avg_pace,
        pace_factor: pace_factor,
        season_avg_points_pace_adjusted: season_avg_points_pace_adjusted
      }.compact
    end

    def legacy_non_points_input(line:, odds:)
      {
        player: { id: @player.id, name: @player.name, team: @player.team },
        stat: @stat_key.to_s,
        season_avg: season_avg,
        last_5_avg: last_5_avg,
        last_10_avg: last_10_avg,
        vs_opponent_avg: vs_opponent_avg,
        std_dev: std_dev,
        variance: variance_rounded,
        coefficient_of_variation: coefficient_of_variation,
        streak_status: streak_status,
        trend: trend_last_5,
        trend_last_10_vs_season: trend_last_10,
        home_avg: home_avg,
        away_avg: away_avg,
        minutes_avg: minutes_avg,
        points_per_minute: (@stat_key == :points ? points_per_minute : nil),
        usage_rate: usage_rate,
        usage_rate_per_minute: usage_rate_per_minute,
        over_line_rate: over_line_rate,
        line: line,
        odds: odds
      }.compact
    end
  end
end
