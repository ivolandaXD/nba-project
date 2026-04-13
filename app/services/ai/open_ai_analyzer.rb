require 'httparty'

module Ai
  class OpenAiAnalyzer
    Result = Struct.new(:ok, :prediction, :structured, :error, keyword_init: true) do
      def success?
        ok
      end
    end

    OPENAI_URL = 'https://api.openai.com/v1/chat/completions'.freeze

    LEGACY_JSON_KEYS = %w[
      scenario_summary
      trend_direction
      line_hit_probability
      probability_estimate
      value_bet
      risk_level
      justification
    ].freeze

    PRO_JSON_KEYS = %w[
      statistical_edge
      context_impact
      true_probability_percent
      ev_assessment
      risk_adjusted
      final_reading
      recommendation
    ].freeze

    JSON_KEYS = (LEGACY_JSON_KEYS + PRO_JSON_KEYS).uniq.freeze

    def self.call(input_hash, model: ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini'))
      new(input_hash, model: model).call
    end

    def initialize(input_hash, model:)
      @input_hash = input_hash
      @model = model
    end

    def call
      key = ENV['OPENAI_API_KEY']
      return Result.new(ok: false, prediction: nil, structured: {}, error: 'OPENAI_API_KEY is not set') if key.blank?

      use_json = ENV.fetch('OPENAI_JSON_RESPONSE', 'true') == 'true'

      body = {
        model: @model,
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: build_user_message }
        ],
        temperature: 0.35
      }
      body[:response_format] = { type: 'json_object' } if use_json

      response = HttpClient.with_retry do
        HTTParty.post(
          OPENAI_URL,
          headers: {
            'Authorization' => "Bearer #{key}",
            'Content-Type' => 'application/json'
          },
          body: body.to_json,
          timeout: 60
        )
      end

      unless response.success?
        return Result.new(ok: false, prediction: nil, structured: {}, error: "OpenAI HTTP #{response.code}: #{response.body}")
      end

      parsed = response.parsed_response
      text = parsed.dig('choices', 0, 'message', 'content')
      return Result.new(ok: false, prediction: nil, structured: {}, error: 'Empty OpenAI response') if text.blank?

      raw = text.to_s.strip
      structured = parse_structured(raw, use_json: use_json)
      unless postgame_mode?
        structured = normalize_structured(structured) if structured.present?
      end

      display =
        if structured.present? && postgame_mode?
          pr = StructuredOutputs::PostgameReview.parse(structured)
          if pr[:ok]
            PostMortemPresenter.to_text(pr[:data])
          else
            <<~TXT.strip
              Revisão recebida, mas o JSON não passou na validação mínima (#{pr[:errors].join(', ')}).
              Trecho bruto (para auditoria):
              #{raw}
            TXT
          end
        elsif structured.present?
          s = structured.stringify_keys
          if portfolio_mode? || professional_mode? || s['prop_suggestions'].present?
            format_display_professional(s)
          else
            format_display(s)
          end
        else
          raw
        end

      Result.new(ok: true, prediction: display, structured: structured, error: nil)
    rescue StandardError => e
      Rails.logger.error("[OpenAiAnalyzer] #{e.class}: #{e.message}")
      Result.new(ok: false, prediction: nil, structured: {}, error: e.message)
    end

    def self.format_display_professional(h)
      h = h.stringify_keys
      core = <<~TXT.strip
        1. Edge estatístico
        #{h['statistical_edge'].presence || '—'}

        2. Impacto do contexto (crítico)
        #{h['context_impact'].presence || '—'}

        3. Probabilidade real (%)
        #{h['true_probability_percent'].presence || '—'}

        4. EV
        #{h['ev_assessment'].presence || '—'}

        5. Risco ajustado
        #{h['risk_adjusted'].presence || '—'}

        6. Leitura final
        #{h['final_reading'].presence || '—'}

        7. Recomendação: #{h['recommendation'].presence || '—'}
      TXT

      pn = h['parlay_note'].presence || h['parlay_correlation_note'].presence
      sug_body = format_prop_suggestions_body(h['prop_suggestions'])
      if pn.present? || sug_body.present?
        block = +'8. Parlay / múltipla e ideias de props'
        block << "\n\nCorrelação (mesmo jogo): #{pn}" if pn.present?
        block << "\n\n#{sug_body}" if sug_body.present?
        "#{core}\n\n#{block}"
      else
        core
      end
    end

    def self.format_prop_suggestions_body(raw)
      return nil if raw.blank?

      items = raw.is_a?(Array) ? raw : []
      lines = []
      items.each do |it|
        next if it.blank?

        x = it.is_a?(Hash) ? it.stringify_keys : {}
        next if x.empty?

        m = x['market'].presence || x['mercado'].presence || '—'
        idea = x['idea'].presence || x['prop_idea'].presence || '—'
        pct = x['estimated_hit_percent'].presence || x['percent'].presence || '—'
        basis = x['based_on'].presence || x['fundamento'].presence || '—'
        lines << "  • #{m} · #{idea} · ~#{pct}\n    Fundamento: #{basis}"
      end
      return nil if lines.empty?

      "Sugestões (combine por sua conta; probabilidades são estimativas, não garantia):\n#{lines.join("\n")}"
    end

    def self.format_display(h)
      h = h.stringify_keys
      prob = h['line_hit_probability'].presence || h['probability_estimate'].presence || '—'
      trend = h['trend_direction'].presence || '—'
      <<~TXT.strip
        1. Resumo do cenário
        #{h['scenario_summary'].presence || '—'}

        2. Tendência: #{trend}
        3. Probabilidade de bater a linha: #{prob}
        4. Nível de risco: #{h['risk_level'].presence || '—'}
        5. Existe valor na aposta? #{h['value_bet'].presence || '—'}

        6. Justificativa
        #{h['justification'].presence || '—'}
      TXT
    end

    def self.normalize_structured(h)
      h = h.stringify_keys

      h['scenario_summary'] ||= h['statistical_edge'] if h['statistical_edge'].present?
      h['justification'] ||= h['final_reading'] if h['final_reading'].present?
      h['risk_level'] ||= h['risk_adjusted'] if h['risk_adjusted'].present?

      rec = h['recommendation'].to_s.downcase
      if h['line_hit_probability'].blank? && rec.present?
        h['line_hit_probability'] =
          if rec.include?('over')
            'alta'
          elsif rec.include?('under')
            'baixa'
          else
            'media'
          end
      end

      h['trend_direction'] ||= 'neutro' if h['context_impact'].present? && h['trend_direction'].blank?

      h['line_hit_probability'] ||= h['probability_estimate'] if h['probability_estimate'].present?
      h['probability_estimate'] ||= h['line_hit_probability'] if h['line_hit_probability'].present?

      ev_txt = h['ev_assessment'].to_s.downcase
      if h['value_bet'].blank? && ev_txt.present?
        h['value_bet'] = 'sim' if ev_txt.include?('positivo') || ev_txt.include?('+')
        h['value_bet'] ||= 'nao' if ev_txt.include?('negativo') || ev_txt.include?('pass')
      end

      h
    end

    private

    # Primeiro bloco: JSON do modelo (sem chaves só de anexo). Depois, opcionalmente:
    # `external_game_context` (JSON) e/ou `external_context_text` (texto longo), alinhado ao pacote play-in.
    def build_user_message
      raw = @input_hash.deep_stringify_keys
      ext_ctx = raw.delete('external_game_context')
      ext_txt = raw.delete('external_context_text')
      msg = +"Dados JSON:\n#{JSON.pretty_generate(raw)}"
      if ext_ctx.present?
        msg << "\n\n---\nexternal_game_context (snapshot curado; pode estar desatualizado):\n"
        msg << JSON.pretty_generate(ext_ctx.is_a?(Hash) ? ext_ctx : { 'value' => ext_ctx })
      end
      if ext_txt.present?
        msg << "\n\n---\nContexto externo (texto):\n#{ext_txt}"
      end
      msg
    end

    def raw_analysis_mode
      (@input_hash[:analysis_mode] || @input_hash['analysis_mode']).to_s
    end

    def postgame_mode?
      AnalysisModes.postgame_review?(raw_analysis_mode)
    end

    def portfolio_mode?
      AnalysisModes.pregame_portfolio?(raw_analysis_mode)
    end

    def professional_mode?
      AnalysisModes.pregame_single_market_pro?(raw_analysis_mode, @input_hash)
    end

    def normalize_structured(h)
      self.class.normalize_structured(h)
    end

    def system_prompt
      return PromptCatalog.postgame_review_system if postgame_mode?
      return PromptCatalog.pregame_portfolio_system if portfolio_mode?
      return PromptCatalog.pregame_single_market_pro_system if professional_mode?

      PromptCatalog.pregame_single_market_legacy_system
    end

    def parse_structured(raw, use_json:)
      return {} unless use_json

      JSON.parse(raw)
    rescue JSON::ParserError
      try_extract_json(raw)
    end

    def try_extract_json(raw)
      if (m = raw.match(/\{[\s\S]*\}/))
        JSON.parse(m[0])
      else
        {}
      end
    rescue JSON::ParserError
      {}
    end
  end
end
