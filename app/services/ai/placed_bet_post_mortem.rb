# frozen_string_literal: true

module Ai
  # Revisão pós-jogo de um bilhete: envia payload compacto à OpenAI e grava texto em placed.ai_post_mortem.
  class PlacedBetPostMortem
    def self.call(placed:, evaluation_note: nil)
      new(placed: placed, evaluation_note: evaluation_note).call
    end

    def initialize(placed:, evaluation_note: nil)
      @placed = placed
      @evaluation_note = evaluation_note
    end

    def call
      if @evaluation_note.present?
        @placed.evaluation_note = @evaluation_note.to_s.strip[0, 5000]
        @placed.save! if @placed.changed?
      end

      payload = PlayerProps::PostMortemPayloadBuilder.call(@placed)

      ai = OpenAiAnalyzer.call(payload)
      unless ai.success?
        return { ok: false, error: ai.error }
      end

      parsed = StructuredOutputs::PostgameReview.parse(ai.structured)
      if parsed[:ok]
        @placed.ai_post_mortem_structured = parsed[:data]
        @placed.ai_post_mortem = PostMortemPresenter.to_text(parsed[:data])
        @placed.ai_post_mortem_parse_error = nil
      else
        # Não persistir JSON parcial como "estruturado válido": só texto de fallback + erro auditável.
        @placed.ai_post_mortem_structured = {}
        @placed.ai_post_mortem_parse_error = "STRUCTURAL_INVALID: #{parsed[:errors].join('; ')}"
        @placed.ai_post_mortem = ai.prediction.to_s
      end

      @placed.ai_post_mortem_at = Time.current
      @placed.save!

      { ok: true, error: nil, prediction: @placed.ai_post_mortem, structured: @placed.ai_post_mortem_structured }
    rescue StandardError => e
      Rails.logger.error("[PlacedBetPostMortem] #{e.class}: #{e.message}")
      { ok: false, error: e.message }
    end
  end
end
