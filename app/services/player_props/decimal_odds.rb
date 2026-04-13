# frozen_string_literal: true

module PlayerProps
  # Odds decimais (EU) → probabilidade implícita e edge em pontos percentuais.
  class DecimalOdds
    def self.implied_probability(decimal_odds)
      d = decimal_odds.to_f
      return nil if d <= 1.0

      1.0 / d
    end

    # Edge em pontos percentuais: (p_est - p_impl) * 100
    def self.edge_percent_points(estimated_probability:, decimal_odds:)
      p = estimated_probability.to_f
      impl = implied_probability(decimal_odds)
      return nil if impl.nil?

      (p - impl) * 100.0
    end

    # EV por unidade apostada no evento binário com probabilidade p de vitória (aproximação).
    def self.ev_binary(p_win:, decimal_odds:)
      d = decimal_odds.to_f
      return nil if d <= 1.0 || p_win.nil?

      p = p_win.to_f
      p * (d - 1.0) - (1.0 - p)
    end
  end
end
