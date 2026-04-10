module Ai
  class GamePlayerAnalysis
    def self.opponent_team_for(player, game)
      return game.away_team if player.team.to_s == game.home_team.to_s
      return game.home_team if player.team.to_s == game.away_team.to_s

      nil
    end

    # confidence_score (kwarg) ignorado: o score 0–100 é sempre calculado por PlayerMetrics::ConfidenceScorer.
    def self.call(game:, player:, line: nil, bet_type: 'points', odds: nil, confidence_score: nil)
      opponent = opponent_team_for(player, game)
      stat_key = bet_type.to_sym
      line_val = line.present? ? line.to_f : nil

      payload = PlayerMetrics::Calculator.cached_payload(
        player,
        stat_key: stat_key,
        line: line_val,
        opponent_team: opponent
      )

      computed = PlayerMetrics::ConfidenceScorer.call(payload[:scorer_inputs])

      input = payload[:for_ai].dup
      input[:odds] = odds if odds.present?
      input[:line] = line_val unless line_val.nil?
      input[:confidence_score_model] = computed

      ai = OpenAiAnalyzer.call(input)
      return { ok: false, error: ai.error, prediction: nil } unless ai.success?

      meta = (ai.structured.presence || {}).stringify_keys.slice(*OpenAiAnalyzer::JSON_KEYS)

      prediction = AiPrediction.create!(
        game: game,
        player: player,
        input_data: input.deep_stringify_keys,
        output_text: ai.prediction,
        confidence_score: computed,
        analysis_meta: meta
      )
      { ok: true, error: nil, prediction: prediction }
    rescue StandardError => e
      Rails.logger.error("[GamePlayerAnalysis] #{e.class}: #{e.message}")
      { ok: false, error: e.message, prediction: nil }
    end
  end
end
