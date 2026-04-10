module PlayerMetrics
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
        s += 22.0 * (1.0 - ratio)
      end

      t5 = @inputs[:trend_last_5]
      if t5.present?
        s += 14 if t5.to_f > 2.0
        s += 8 if t5.to_f > 0.5 && t5.to_f <= 2.0
        s += 4 if t5.to_f > 0 && t5.to_f <= 0.5
        s -= 14 if t5.to_f < -2.0
        s -= 8 if t5.to_f < -0.5 && t5.to_f >= -2.0
        s -= 4 if t5.to_f < 0 && t5.to_f >= -0.5
      end

      l5 = @inputs[:last_5_avg]
      savg = @inputs[:season_avg]
      if l5.present? && savg.present? && l5.to_f > savg.to_f + 1.5
        s += 6
      elsif l5.present? && savg.present? && l5.to_f < savg.to_f - 1.5
        s -= 6
      end

      ol = @inputs[:over_line_rate]
      if ol.present? && @inputs[:line].present?
        s += 18.0 * (ol.to_f / 100.0)
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
