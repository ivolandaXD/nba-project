# frozen_string_literal: true

module Ai
  # Modos canónicos de análise IA + mapa único legado → canônico.
  #
  # DEPRECATED (payloads antigos / prompts antigos — remover numa major futura):
  #   - "points_props_pro"        → pregame_single_market (payload com decision_score)
  #   - "props_portfolio"         → pregame_portfolio
  #   - "post_mortem_bet_review"  → postgame_review
  #   - "legacy_points_prompt"    → pregame_single_market
  #
  # Novos códigos devem usar apenas os valores canónicos em `analysis_mode`.
  module AnalysisModes
    PREGAME_SINGLE_MARKET = 'pregame_single_market'
    PREGAME_PORTFOLIO = 'pregame_portfolio'
    POSTGAME_REVIEW = 'postgame_review'

    # Única fonte de verdade: chave = valor persistido legado; valor = modo canônico.
    LEGACY_TO_CANONICAL = {
      'points_props_pro' => PREGAME_SINGLE_MARKET,
      'props_portfolio' => PREGAME_PORTFOLIO,
      'post_mortem_bet_review' => POSTGAME_REVIEW,
      'legacy_points_prompt' => PREGAME_SINGLE_MARKET
    }.freeze

    DEPRECATED_MODES = LEGACY_TO_CANONICAL.keys.freeze

    CANONICAL_MODES = [
      PREGAME_SINGLE_MARKET,
      PREGAME_PORTFOLIO,
      POSTGAME_REVIEW
    ].freeze

    module_function

    def canonical(raw)
      k = raw.to_s.strip
      LEGACY_TO_CANONICAL[k] || k
    end

    def deprecated?(raw)
      DEPRECATED_MODES.include?(raw.to_s.strip)
    end

    def postgame_review?(raw_mode, **_opts)
      canonical(raw_mode) == POSTGAME_REVIEW
    end

    def pregame_portfolio?(raw_mode, **_opts)
      canonical(raw_mode) == PREGAME_PORTFOLIO
    end

    # Modo "pro" de mercado único: payload traz decision_score (heurística numérica combinada).
    def pregame_single_market_pro?(raw_mode, input_hash)
      return true if raw_mode.to_s == 'points_props_pro'

      canonical(raw_mode) == PREGAME_SINGLE_MARKET && pro_payload?(input_hash)
    end

    def pro_payload?(input_hash)
      h = input_hash || {}
      h[:decision_score].present? || h['decision_score'].present?
    end
  end
end
