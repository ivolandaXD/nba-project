module PlayerProps
  class ManualContext
    PERMITTED_KEYS = %i[
      injuries_text
      returning_players_text
      opponent_defense_rank_vs_position
      opponent_rebounds_allowed_rank
      pace
      is_back_to_back
      home_context
      spread
      key_teammate_out
      matchup_favorable
    ].freeze

    # Strong parameters para formulários web e JSON da API.
    def self.permit_params(params, *extra_keys)
      p = params.respond_to?(:permit) ? params : ActionController::Parameters.new(params)
      p.permit(
        *extra_keys.flatten,
        *PERMITTED_KEYS,
        manual_context: [*PERMITTED_KEYS, { injuries: [], returning_players: [] }]
      )
    end

    def self.parse_player_list(text)
      text.to_s.split(/[\n,;]/).map(&:strip).reject(&:blank?)
    end

    def self.resolve_is_home(player, game, home_context)
      case home_context.to_s
      when 'home' then true
      when 'away' then false
      else
        player.team.to_s.strip == game.home_team.to_s.strip
      end
    end

    def self.from_params(params, player:, game:)
      p = params.respond_to?(:permit) ? params : ActionController::Parameters.new(params)
      flat = p.permit(*PERMITTED_KEYS).to_h.symbolize_keys

      nested =
        case p[:manual_context]
        when ActionController::Parameters
          p[:manual_context].permit(*PERMITTED_KEYS, injuries: [], returning_players: []).to_h.symbolize_keys
        when Hash
          p[:manual_context].deep_symbolize_keys.slice(*(PERMITTED_KEYS + %i[injuries returning_players]))
        else
          {}
        end

      flat = flat.merge(nested) { |_k, a, b| b.present? || b == false ? b : a }

      flat[:is_back_to_back] = ActiveModel::Type::Boolean.new.cast(flat[:is_back_to_back])
      flat[:matchup_favorable] = ActiveModel::Type::Boolean.new.cast(flat[:matchup_favorable])

      from_hash(flat, player: player, game: game)
    end

    def self.from_hash(raw, player:, game:)
      raw = {} if raw.nil?
      h = raw.deep_symbolize_keys

      injuries =
        if h[:injuries].is_a?(Array)
          h[:injuries].map(&:to_s).map(&:strip).reject(&:blank?)
        else
          parse_player_list(h[:injuries_text] || h[:injuries])
        end

      returning =
        if h[:returning_players].is_a?(Array)
          h[:returning_players].map(&:to_s).map(&:strip).reject(&:blank?)
        else
          parse_player_list(h[:returning_players_text] || h[:returning])
        end

      home_context = h[:home_context].presence
      if h.key?(:is_home) && home_context.blank?
        home_context = ActiveModel::Type::Boolean.new.cast(h[:is_home]) ? 'home' : 'away'
      end

      {
        injuries: injuries,
        returning_players: returning,
        opponent_defense_rank_vs_position: h[:opponent_defense_rank_vs_position].presence&.to_s&.strip,
        opponent_rebounds_allowed_rank: h[:opponent_rebounds_allowed_rank].presence&.to_s&.strip,
        pace: h[:pace].presence&.to_s&.strip&.downcase,
        is_back_to_back: ContextAdjustor.truthy?(h[:is_back_to_back]),
        is_home: resolve_is_home(player, game, home_context),
        spread: h[:spread].presence,
        key_teammate_out: h[:key_teammate_out].presence&.to_s&.strip,
        matchup_favorable: ContextAdjustor.truthy?(h[:matchup_favorable])
      }
    end
  end
end
