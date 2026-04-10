module PlayerProps
  # Odds americanas → probabilidade implícita e EV do over (unidade apostada = 1).
  class AmericanOdds
    def self.implied_probability(odds_str)
      return nil if odds_str.blank?

      o = odds_str.to_s.gsub(/\s/, '').strip
      return nil if o.empty? || o == '-'

      if o.start_with?('-')
        absv = o[1..-1].to_f
        return nil if absv <= 0

        absv / (absv + 100.0)
      else
        v = o.to_f
        return nil if v <= 0

        100.0 / (v + 100.0)
      end
    end

    # EV por $1 apostado no over, dado p = P(ganhar a aposta over).
    def self.ev_over(p:, american_odds:)
      return nil if p.nil? || american_odds.blank?

      o = american_odds.to_s.gsub(/\s/, '').strip
      if o.start_with?('-')
        absv = o[1..-1].to_f
        return nil if absv <= 0

        win_units = 100.0 / absv
        p.to_f * win_units - (1.0 - p.to_f)
      else
        v = o.to_f
        return nil if v <= 0

        win_units = v / 100.0
        p.to_f * win_units - (1.0 - p.to_f)
      end
    end
  end
end
