require 'httparty'

module Ai
  class OpenAiAnalyzer
    Result = Struct.new(:ok, :prediction, :structured, :error, keyword_init: true) do
      def success?
        ok
      end
    end

    OPENAI_URL = 'https://api.openai.com/v1/chat/completions'.freeze

    JSON_KEYS = %w[
      scenario_summary
      probability_estimate
      value_bet
      risk_level
      justification
    ].freeze

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
          { role: 'user', content: "Dados JSON:\n#{JSON.pretty_generate(@input_hash)}" }
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
      display = structured.present? ? self.class.format_display(structured) : raw

      Result.new(ok: true, prediction: display, structured: structured, error: nil)
    rescue StandardError => e
      Rails.logger.error("[OpenAiAnalyzer] #{e.class}: #{e.message}")
      Result.new(ok: false, prediction: nil, structured: {}, error: e.message)
    end

    def self.format_display(h)
      h = h.stringify_keys
      <<~TXT.strip
        1. Resumo do cenário
        #{h['scenario_summary'].presence || '—'}

        2. Probabilidade estimada: #{h['probability_estimate'].presence || '—'}
        3. Existe valor na aposta? #{h['value_bet'].presence || '—'}
        4. Nível de risco: #{h['risk_level'].presence || '—'}

        5. Justificativa
        #{h['justification'].presence || '—'}
      TXT
    end

    private

    def system_prompt
      (<<~PROMPT).squish
        Você é um analista esportivo especializado em NBA.

        Analise os dados considerando:
        - Consistência (desvio padrão e coeficiente de variação)
        - Tendência recente (últimos 10 vs temporada)
        - Frequência de jogos acima da linha e faixas (15/20/25 pts quando aplicável)
        - Volume de jogo (minutos médios, pontos por minuto, uso ofensivo proxy FGA+FTA)
        - Histórico contra o adversário e streak (hot/cold/neutral)

        Responda de forma estruturada em JSON com exatamente estas chaves (strings):
        "scenario_summary", "probability_estimate" (uma de: baixa, media, alta),
        "value_bet" (uma de: sim, nao), "risk_level" (uma de: baixo, medio, alto),
        "justification".

        Use "media" e "medio" sem acento nos valores enum para facilitar o parse.
        Seja objetivo e evite respostas genéricas; cite números do input quando possível.
      PROMPT
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
