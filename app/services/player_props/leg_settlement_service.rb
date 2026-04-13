# frozen_string_literal: true

module PlayerProps
  # Preenche actual_value / delta / result_status por perna usando box score (quando há match seguro).
  class LegSettlementService
    STAT_MAP = {
      'points' => :points,
      'rebounds' => :rebounds,
      'assists' => :assists,
      'threes' => :three_pt_made,
      'steals' => :steals,
      'blocks' => :blocks,
      'turnovers' => :turnovers
    }.freeze

    def self.call(placed)
      new(placed).call
    end

    def initialize(placed)
      @placed = placed
    end

    def call
      return if @placed.blank?

      @placed.placed_ai_suggestion_legs.find_each do |leg|
        settle_leg!(leg)
      end
    end

    private

    def settle_leg!(leg)
      leg.reload
      meta = (leg.metadata.is_a?(Hash) ? leg.metadata.deep_dup : {})

      if leg.game_id.blank? || leg.player_id.blank? || leg.line_value.blank? || leg.selection_type.blank?
        meta['settlement'] = 'skipped_missing_link'
        leg.update_columns(result_status: 'pending', actual_value: nil, delta_vs_line: nil, metadata: meta)
        return
      end

      col = STAT_MAP[leg.market_type]
      if col.nil? || leg.market_type == 'unknown'
        meta['settlement'] = 'unknown_market'
        leg.update_columns(result_status: 'pending', metadata: meta)
        return
      end

      pgs = PlayerGameStat.find_by(game_id: leg.game_id, player_id: leg.player_id)
      unless pgs
        meta['settlement'] = 'no_box_score'
        leg.update_columns(result_status: 'pending', metadata: meta)
        return
      end

      actual = pgs.public_send(col)
      actual_f = actual.nil? ? nil : actual.to_f
      line = leg.line_value.to_f
      delta = (actual_f.nil? ? nil : (actual_f - line))

      status =
        if actual_f.nil?
          'pending'
        else
          compare_selection(leg.selection_type, actual_f, line)
        end

      meta['settlement'] = 'from_player_game_stat'
      meta['settled_at'] = Time.current.iso8601

      leg.update_columns(
        actual_value: actual_f,
        delta_vs_line: delta,
        result_status: status,
        metadata: meta
      )
    end

    def compare_selection(selection, actual, line)
      a = actual.to_f
      l = line.to_f
      return 'push' if (a - l).abs <= 1e-9

      if selection == 'over'
        a > l ? 'hit' : 'miss'
      else # under
        a < l ? 'hit' : 'miss'
      end
    end
  end
end
