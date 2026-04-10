module PlayerMetrics
  # Score 0–100 a partir de consistência, tendência, linha e streak (determinístico).
  class ConfidenceScorer
    def self.call(inputs)
      new(inputs).score
    end

    def initialize(inputs)
      @inputs = inputs.symbolize_keys
    end

    def score
      s = 50.0

      cv = @inputs[:coefficient_of_variation]
      if cv.present? && cv.to_f >= 0
        cap = 1.2
        ratio = [cv.to_f, cap].min / cap
        s += 25.0 * (1.0 - ratio)
      end

      trend = @inputs[:trend_last_10]
      if trend.present?
        s += 12 if trend.to_f > 1.0
        s += 5 if trend.to_f > 0 && trend.to_f <= 1.0
        s -= 12 if trend.to_f < -2.0
        s -= 5 if trend.to_f < 0 && trend.to_f >= -2.0
      end

      ol = @inputs[:over_line_rate]
      if ol.present? && @inputs[:line].present?
        s += 20.0 * (ol.to_f / 100.0)
      elsif @inputs[:over_20_rate].present?
        s += 10.0 * (@inputs[:over_20_rate].to_f / 100.0)
      end

      case @inputs[:streak_status].to_s
      when 'hot'
        s += 8
      when 'cold'
        s -= 8
      end

      [[s.round, 100].min, 0].max
    end
  end
end
