# frozen_string_literal: true

module PlayerProps
  # Sincroniza `placed_ai_suggestions.legs` (JSONB) → linhas em `placed_ai_suggestion_legs`.
  class PlacedLegsSyncService
    def self.call(placed)
      new(placed).call
    end

    def initialize(placed)
      @placed = placed
    end

    def call
      return if @placed.blank?

      @placed.placed_ai_suggestion_legs.destroy_all
      legs = Array(@placed.legs)
      return if legs.empty?

      legs.each_with_index do |raw, idx|
        h = raw.is_a?(Hash) ? raw.stringify_keys : {}
        norm = LegMarketNormalizer.call(h)
        match = LegMatcher.call(placed: @placed, leg_hash: h, leg_index: idx)

        odds_dec = h['odds_decimal'].presence || h['decimal_odds'].presence
        implied = DecimalOdds.implied_probability(odds_dec)
        est = h['estimated_hit_probability'].presence&.to_f
        edge =
          if est && implied && odds_dec.present?
            DecimalOdds.edge_percent_points(estimated_probability: est, decimal_odds: odds_dec)
          end

        team_abbr = TeamAbbr.normalize(match.team_abbr)

        @placed.placed_ai_suggestion_legs.create!(
          leg_index: idx,
          sport: h['sport'].presence || 'nba',
          event_label: h['event'].presence,
          game_id: match.game_id,
          player_id: match.player_id,
          team_abbr: team_abbr,
          market_type: norm.market_type,
          selection_type: norm.selection_type,
          line_value: norm.line_value,
          odds_decimal: h['odds_decimal'].presence || h['decimal_odds'],
          result_status: 'pending',
          model_confidence_score: h['model_confidence_score'].presence,
          estimated_hit_probability: est,
          market_implied_probability: implied,
          edge_percent_points: edge,
          ev_estimate: h['ev_estimate'].presence,
          matched_confidence: match.matched_confidence,
          match_method: match.match_method,
          source_payload: match.source_payload,
          metadata: {
            'normalized' => {
              'market_type' => norm.market_type,
              'selection_type' => norm.selection_type,
              'line_value' => norm.line_value
            },
            'synced_at' => Time.current.iso8601
          }
        )
      end
    end
  end
end
