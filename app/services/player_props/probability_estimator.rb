module PlayerProps
  # Heurística simples P(over na linha) a partir de game logs agregados.
  class ProbabilityEstimator
    def self.over_probability(metrics_hash, line:)
      h = metrics_hash.stringify_keys
      line_f = line&.to_f
      ol = h['over_line_rate']

      if ol.present? && line_f.present?
        return [[ol.to_f / 100.0, 0.05].max, 0.95].min
      end

      l5 = h['last_5_avg_points']&.to_f
      s = h['season_avg_points']&.to_f
      std = h['std_dev_points']&.to_f
      ref = l5 || s
      return 0.5 if line_f.nil? || ref.nil?

      if std.present? && std.positive?
        z = (line_f - ref) / std
        p = 1.0 - normal_cdf(z)
      else
        delta = ref - line_f
        p = 0.5 + [[delta * 0.04, 0.22].min, -0.22].max
      end

      [[p, 0.05].max, 0.95].min
    end

    def self.normal_cdf(x)
      0.5 * (1.0 + Math.erf(x / Math.sqrt(2.0)))
    end
  end
end
