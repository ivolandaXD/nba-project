module PlayerProps
  # Score 0–100: modelo + probabilidade ajustada + EV + consistência + contexto.
  class DecisionScorer
    def self.call(model_score:, adjusted_probability:, ev:, context_modifier_total:, coefficient_of_variation: nil)
      ms = model_score.to_f.clamp(0, 100)
      ap = adjusted_probability.to_f.clamp(0, 1)

      ev_n =
        if ev.nil?
          50.0
        else
          e = ev.to_f
          [[((e + 0.25) / 0.5) * 100.0, 0.0].max, 100.0].min
        end

      cv = coefficient_of_variation.to_f
      cons =
        if cv.positive?
          (100.0 * (1.0 - [cv / 0.5, 1.0].min)).clamp(0.0, 100.0)
        else
          55.0
        end

      ctx = (50.0 + context_modifier_total.to_f * 120.0).clamp(0.0, 100.0)

      (
        ms * 0.38 +
        ap * 100.0 * 0.22 +
        ev_n * 0.18 +
        cons * 0.12 +
        ctx * 0.10
      ).round.clamp(0, 100)
    end
  end
end
