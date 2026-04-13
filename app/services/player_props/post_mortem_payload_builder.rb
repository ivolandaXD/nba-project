# frozen_string_literal: true

module PlayerProps
  # Payload canônico pós-jogo: `analysis_mode: postgame_review`, ticket, pernas auditáveis, qualidade de dados.
  class PostMortemPayloadBuilder
    def self.call(placed)
      new(placed).to_h
    end

    def initialize(placed)
      @placed = placed
    end

    def to_h
      @placed.resync_legs! if @placed.persisted?

      {
        analysis_mode: Ai::AnalysisModes::POSTGAME_REVIEW,
        legacy_analysis_mode: 'post_mortem_bet_review',
        ticket: ticket_block,
        legs: legs_payload,
        user_review: {
          evaluation_note: @placed.evaluation_note.to_s.strip.presence,
          ticket_result: @placed.result
        },
        review_goals: {
          distinguish_variance_vs_process: true,
          flag_weak_matching: true,
          never_invent_missing_box_score: true
        },
        matched_box_scores: matched_box_scores,
        data_quality: data_quality_block,
        meta: {
          built_at: Time.current.iso8601,
          note: 'Pernas estruturadas vêm de placed_ai_suggestion_legs (sync a partir do JSONB). Matching fraco reduz confiança da revisão.'
        }
      }.compact
    end

    private

    def ticket_block
      {
        id: @placed.id,
        slip_kind: @placed.slip_kind,
        description: @placed.description,
        result: @placed.result,
        decimal_odds: @placed.decimal_odds&.to_f,
        stake_brl: @placed.stake_brl&.to_f,
        external_bet_id: @placed.external_bet_id,
        game_id: @placed.game_id
      }.compact
    end

    def legs_payload
      rows = @placed.placed_ai_suggestion_legs.ordered
      return legacy_legs_if_empty(rows) if rows.none?

      rows.map { |leg| leg_payload(leg) }
    end

    def legacy_legs_if_empty(_rows)
      Array(@placed.legs).each_with_index.map do |raw, idx|
        h = raw.is_a?(Hash) ? raw.stringify_keys : {}
        {
          leg_index: idx,
          raw: h,
          note: 'sem_registro_estruturado_ainda'
        }
      end
    end

    def leg_payload(leg)
      {
        leg_index: leg.leg_index,
        event_label: leg.event_label,
        sport: leg.sport,
        market_type: leg.market_type,
        selection_type: leg.selection_type,
        line_value: leg.line_value&.to_f,
        odds_decimal: leg.odds_decimal&.to_f,
        result_status: leg.result_status,
        actual_value: leg.actual_value&.to_f,
        delta_vs_line: leg.delta_vs_line&.to_f,
        game_id: leg.game_id,
        player_id: leg.player_id,
        team_abbr: leg.team_abbr,
        match_method: leg.match_method,
        matched_confidence: leg.matched_confidence&.to_f,
        model_confidence_score: leg.model_confidence_score&.to_f,
        estimated_hit_probability: leg.estimated_hit_probability&.to_f,
        market_implied_probability: leg.market_implied_probability&.to_f,
        edge_percent_points: leg.edge_percent_points&.to_f,
        ev_estimate: leg.ev_estimate&.to_f
      }.compact
    end

    def matched_box_scores
      rows = []
      @placed.placed_ai_suggestion_legs.ordered.each do |leg|
        next if leg.game_id.blank? || leg.player_id.blank?

        game = Game.find_by(id: leg.game_id)
        player = Player.find_by(id: leg.player_id)
        next unless game && player

        pgs = PlayerGameStat.find_by(game_id: game.id, player_id: player.id)
        rows << {
          leg_index: leg.leg_index,
          player: player.name,
          game: "#{game.away_team} @ #{game.home_team}",
          box: pgs ? box_hash(pgs) : { note: 'sem box score importado para este jogo' },
          match_method: leg.match_method,
          matched_confidence: leg.matched_confidence&.to_f
        }.compact
      end

      rows
    end

    def data_quality_block
      legs = @placed.placed_ai_suggestion_legs.ordered.to_a
      weak = legs.count(&:weak_match?)
      min_conf = legs.map(&:matched_confidence).compact.min

      {
        data_sufficiency: legs.any? ? 'partial_or_full' : 'missing_structured_legs',
        box_score_coverage: legs.any? { |l| l.game_id.present? && l.player_id.present? } ? 'partial' : 'none',
        opponent_split_coverage: 'unknown',
        injury_context_freshness: 'unknown',
        missing_fields: legs.empty? ? %w[structured_legs] : [],
        pregame_data_quality: 'n/a',
        postgame_data_quality: matched_box_scores.any? ? 'partial' : 'low',
        weak_match_leg_count: weak,
        min_matched_confidence: min_conf,
        review_confidence_penalty: weak.positive? || min_conf.to_f < 0.9
      }.compact
    end

    def box_hash(pgs)
      {
        minutes: pgs.minutes&.to_f,
        points: pgs.points,
        rebounds: pgs.rebounds,
        assists: pgs.assists,
        threes_made: pgs.three_pt_made,
        steals: pgs.steals,
        blocks: pgs.blocks,
        turnovers: pgs.turnovers
      }
    end
  end
end
