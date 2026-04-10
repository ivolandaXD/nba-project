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
          { role: 'user', content: "Dados JSON:\n#{JSON.pretty_generate(@input_hash.deep_stringify_keys)}" }
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
      structured = normalize_structured(structured) if structured.present?
      display =
        if structured.present?
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

    def professional_mode?
      m = @input_hash[:analysis_mode] || @input_hash['analysis_mode']
      m.to_s == 'points_props_pro'
    end

    def portfolio_mode?
      m = @input_hash[:analysis_mode] || @input_hash['analysis_mode']
      m.to_s == 'props_portfolio'
    end

    def normalize_structured(h)
      self.class.normalize_structured(h)
    end

    def system_prompt
      return portfolio_prompt if portfolio_mode?
      return professional_points_prompt if professional_mode?

      legacy_points_prompt
    end

    def portfolio_prompt
      (<<~PROMPT).squish
        Você é um analista NBA de player props. O JSON traz "markets_data": por mercado (points, rebounds, assists, threes, steals, blocks, turnovers)
        com médias de temporada, últimos 5 e 10 jogos, vs adversário quando existir, desvio/consistência e minutos.
        "primary_market" e "primary_line" são a aposta de referência (se houver linha); "odds" é opcional.
        Use "manual_game_context", "opponent_split", "opponent_team_stats" e notas do usuário quando existirem.

        Objetivo: NÃO depender de uma única aposta fechada. Entregue 3 a 6 ideias de props (ex.: 20+ PTS, 2+ 3PM, 8+ REB, 4+ AST)
        coerentes com os números, cada uma com "estimated_hit_percent" (percentual ou faixa curta) e "based_on" citando explicitamente
        média temporada, L5, L10 e vs adversário quando disponíveis.

        Inclua "parlay_note": lembre que num same-game parlay os mercados não são independentes (correlação positiva entre PTS e 3PM, etc.).

        Responda em JSON com chaves:
        "statistical_edge", "context_impact", "true_probability_percent", "ev_assessment" (use odds se existirem; senão texto sobre valor qualitativo),
        "risk_adjusted" (baixo, medio ou alto — sem acento),
        "final_reading", "recommendation" (OVER, UNDER, PASS ou NEUTRO conforme primary_line),
        "parlay_note",
        "prop_suggestions": array de objetos {"market","idea","estimated_hit_percent","based_on"},
        e chaves legadas: "scenario_summary", "trend_direction", "line_hit_probability", "probability_estimate", "value_bet", "risk_level", "justification".
        Use "media" e "medio" sem acento onde aplicável.
      PROMPT
    end

    def professional_points_prompt
      (<<~PROMPT).squish
        Você é um analista profissional de apostas NBA especializado em player props (pontos).

        Sua análise deve combinar:
        1) Dados estatísticos (probability_over, implied_probability, ev, adjusted_probability, confidence_score_model, tendência, consistência).
        2) Contexto de jogo em manual_game_context / injuries / pace / is_back_to_back / is_home / spread / opponent_defense_rank_vs_position / returning_players.

        Analise:
        Estatística: probabilidade real vs implícita, EV (use o campo "ev" quando existir), tendência recente, consistência (std_dev_points, coefficient_of_variation).
        Contexto: desfalques e retornos (impacto em uso ofensivo), matchup defensivo vs posição, ritmo (pace), risco de blowout (|spread| alto), fadiga (back-to-back).

        Regras: contexto muito negativo reduz confiança; muito positivo aumenta; EV positivo com contexto ruim pode justificar PASS.
        Seja técnico e direto; cite números do JSON.

        Responda em JSON com exatamente estas chaves (strings):
        "statistical_edge",
        "context_impact",
        "true_probability_percent" (ex.: "58%" ou intervalo curto),
        "ev_assessment" (texto curto referindo EV do input),
        "risk_adjusted" (baixo, medio ou alto — sem acento: medio),
        "final_reading" (síntese),
        "recommendation" (uma de: OVER, UNDER, PASS — maiúsculas),

        e também as chaves legadas para compatibilidade:
        "scenario_summary" (pode repetir resumo do edge),
        "trend_direction" (alta, queda ou neutro),
        "line_hit_probability" (baixa, media ou alta — chance percebida de bater over na linha),
        "probability_estimate" (igual a line_hit_probability),
        "value_bet" (sim ou nao),
        "risk_level" (igual a risk_adjusted: baixo, medio, alto),
        "justification" (texto objetivo).

        Use "media" e "medio" sem acento nos enums em português onde aplicável.
      PROMPT
    end

    def legacy_points_prompt
      (<<~PROMPT).squish
        Você é um analista esportivo especializado em NBA, focado em apostas de pontos (player props over/under).

        Analise os dados do jogador considerando:
        - Média da temporada vs forma recente (últimos 5 e 10 jogos)
        - Frequência de jogos acima da linha (over_line_rate) e faixas 15/20/25 pontos
        - Consistência: desvio padrão (std_dev_points) e coeficiente de variação
        - Volume: minutos médios, FGA e FTA médios
        - Histórico contra o adversário (vs_opponent_avg_points, opponent_split)
        - Contexto casa/fora (home_avg_points, away_avg_points)
        - Médias do time adversário na liga (opponent_team_stats), se existirem
        - confidence_score_model no JSON é um score interno 0–100; use como pista, não como única verdade

        Responda em JSON com exatamente estas chaves (strings):
        "scenario_summary" (texto),
        "trend_direction" (uma de: alta, queda, neutro),
        "line_hit_probability" (uma de: baixa, media, alta) — chance de o jogador superar a linha de pontos (over),
        "probability_estimate" (repetir o mesmo valor que line_hit_probability para compatibilidade),
        "value_bet" (uma de: sim, nao),
        "risk_level" (uma de: baixo, medio, alto),
        "justification" (texto objetivo citando números do input).

        Use "media" e "medio" sem acento nos enums.
        Seja objetivo; evite frases genéricas.
        Se existir "user_note", incorpore na justificativa.
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
