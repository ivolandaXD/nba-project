# frozen_string_literal: true

# Gera um ficheiro .txt por jogo no formato "copiar/colar" para o ChatGPT / API:
#   (1) SYSTEM PROMPT — texto em play_in_2026_research/prompts/play_in_portfolio_system_exact.txt
#   (2) USER — "Dados JSON:" (placeholder + comando export) + "external_game_context:" (JSON preenchido)
# Opcional: PLAY_IN_PACKAGE_APPENDIX=1 acrescenta recorte Parte 5, estudo auxiliar e notas de DB.
#
# Uso:
#   bin/rails ai:play_in_openai_package
#   bin/rails ai:play_in_context_send_package   # TXT leve: estudo + resumo + prompt + placeholder (sem portfolio JSON)
#
# Opções:
#   OUT_DIR=play_in_2026_research/generated_openai_packages
#   PLAY_IN_GAME_IDS=10,20,30,40   # ordem: jogo 1 (MIA@CHA) … jogo 4 (POR@PHX)
#   PLAY_IN_ON_DATE=2026-04-15     # opcional — filtra Game.game_date (tem prioridade sobre a janela)
#   PLAY_IN_DATE_FROM / PLAY_IN_DATE_TO  # janela padrão 2026-04-11..2026-04-22 se não definir ON_DATE
#   PLAY_IN_NO_DATE_FILTER=1       # não aplicar janela nem defaults (útil para depuração)
#   PLAY_IN_PACKAGE_APPENDIX=1    # acrescenta Parte 5+6 do template, estudo auxiliar e secção DB ao fim do .txt
#   PLAY_IN_SKIP_EMBEDDED_EXPORT=1 # não embutir JSON do Ai::GamePayloadExporter (só placeholder + comando)
#   PLAY_IN_EMBED_EXPORT_MAX_CHARS=400000 # truncar JSON embutido (0 = sem limite)
#
# OpenAI (app): jogos play-in recebem automaticamente `external_game_context` no user message.
#   OPENAI_SKIP_PLAY_IN_CONTEXT=1  — não anexar
#   OPENAI_ATTACH_PLAY_IN_RESEARCH=1 — anexar também o .txt completo do estudo auxiliar (muitos tokens)
#
# Pacote leve (play_in_context_send_package):
#   PLAY_IN_SEND_PROMPT_REL=play_in_2026_research/prompts/play_in_portfolio_system_exact.txt
#
namespace :ai do
  desc <<-DESC.squish
    Gera um TXT por jogo (SYSTEM + USER no formato copy/paste) + external_game_context.
    Ver prompts/play_in_portfolio_system_exact.txt, OUT_DIR, PLAY_IN_GAME_IDS, datas e PLAY_IN_PACKAGE_APPENDIX.
  DESC
  task play_in_openai_package: :environment do
    require Rails.root.join('app/services/ai/play_in_2026_context').to_s
    require Rails.root.join('app/services/ai/game_payload_exporter').to_s
    PlayInOpenaiPackageGenerator.call
  end

  desc <<-DESC.squish
    Gera um TXT leve por jogo para enviar: contexto auxiliar (estudo + lesões/book/notas), prompt de análise,
    external_game_context e esqueleto de export SEM players/portfolio_input (substituir depois pelo JSON real).
    Ver PLAY_IN_SEND_PROMPT_REL, OUT_DIR, PLAY_IN_GAME_IDS. Não chama GamePayloadExporter.
  DESC
  task play_in_context_send_package: :environment do
    require Rails.root.join('app/services/ai/play_in_2026_context').to_s
    PlayInContextSendPackage.call
  end
end

module PlayInOpenaiPackageGenerator
  module_function

    TEMPLATE_REL = 'play_in_2026_research/openai_input_payload_e_contexto_jogos.txt'
    COPY_PASTE_SYSTEM_REL = 'play_in_2026_research/prompts/play_in_portfolio_system_exact.txt'

    def call
      root = Rails.root
      system_path = root.join(COPY_PASTE_SYSTEM_REL)
      raise "System prompt em falta: #{system_path}" unless system_path.file?

      system_body = system_path.read.rstrip
      template_text = read_optional_template(root)

      out_dir = root.join(ENV.fetch('OUT_DIR', 'play_in_2026_research/generated_openai_packages'))
      FileUtils.mkdir_p(out_dir)

      id_list = parse_optional_game_ids
      on_date = parse_optional_date('PLAY_IN_ON_DATE')

      ::Ai::PlayIn2026Context::MATCHUPS.each do |m|
        game = resolve_game(m, id_list, on_date)
        research_path = root.join('play_in_2026_research', m[:research])
        research_body = research_path.file? ? research_path.read : "(ficheiro em falta: #{m[:research]})\n"

        external_json = ::Ai::PlayIn2026Context.build_package_hash(m, game)
        db_section = build_db_section(game, m)
        export_cmd = build_export_command(game)
        embedded_json = embed_export_json(game)

        doc = []
        doc << meta_header(root, m, game, research_path, system_path, embedded_json.present?)
        doc << section('SYSTEM PROMPT (COPIA EXATAMENTE ISSO)', system_body)
        doc << user_copy_block(m, game, export_cmd, external_json, embedded_json)
        doc << optional_appendix(template_text, m, research_body, db_section)

        out_path = out_dir.join(m[:outfile])
        File.write(out_path, doc.join("\n"))
        puts "Gerado → #{out_path}"
      end

      puts "Concluído (#{::Ai::PlayIn2026Context::MATCHUPS.size} ficheiros em #{out_dir})."
    end

    def read_optional_template(root)
      p = root.join(TEMPLATE_REL)
      p.file? ? p.read : nil
    end

    def meta_header(root, m, game, research_path, system_path, embedded)
      lines = []
      lines << '=' * 80
      lines << 'PACOTE COPY/PASTE — PLAY-IN 2026 (bin/rails ai:play_in_openai_package)'
      lines << "Slug: #{m[:slug]} · Gerado em: #{Time.current.utc.iso8601} UTC"
      lines << "System prompt: #{system_path.relative_path_from(root)}"
      lines << "Estudo auxiliar: #{research_path.relative_path_from(root)}"
      lines << "GAME_ID resolvido: #{game ? game.id : '(nenhum — defina PLAY_IN_GAME_IDS ou PLAY_IN_ON_DATE)'}"
      lines << "JSON do export embutido em \"Dados JSON\": #{embedded ? 'sim (players, L5/L10, odds_snapshots, …)' : 'não — só placeholder; o modelo não tem stats para EV'}"
      lines << "Apêndice longo (Parte 5 + estudo + DB): #{appendix_enabled? ? 'sim (PLAY_IN_PACKAGE_APPENDIX=1)' : 'não (defina PLAY_IN_PACKAGE_APPENDIX=1 para incluir)'}"
      lines << '=' * 80
      lines << ''
      lines.join("\n")
    end

    def appendix_enabled?
      ENV['PLAY_IN_PACKAGE_APPENDIX'].to_s == '1'
    end

    def user_copy_block(m, game, export_cmd, external_json, embedded_json)
      lines = []
      lines << '=' * 80
      lines << 'USER MESSAGE — COLE NO CHAT COMO MENSAGEM DO UTILIZADOR (A SEGUIR AO SYSTEM)'
      lines << '=' * 80
      lines << ''
      lines << 'Dados JSON:'
      lines << dados_json_instructions(m, game, export_cmd, embedded_json)
      lines << ''
      lines << 'external_game_context:'
      lines << JSON.pretty_generate(external_json)
      lines << ''
      lines.join("\n")
    end

    def dados_json_instructions(m, game, export_cmd, embedded_json)
      if embedded_json.present?
        intro = <<~INTRO.strip
          (Bloco seguinte = JSON completo de Ai::GamePayloadExporter: players[].portfolio_input com L5/L10, odds_snapshots, team_season_stats, openai.system_prompts, etc.
          Se odds_snapshots estiver [], o modelo pode recusar EV numérico — importe odds ou preencha manualmente.)
        INTRO
        foot = <<~FT.strip
          (Para regenerar / atualizar: #{export_cmd})
          O export pode já incluir "external_game_context" na raiz — a secção "external_game_context:" abaixo no .txt repete o snapshot curado para leitura rápida.
        FT
        return [intro, embedded_json, foot].join("\n\n")
      end

      game_id_json = game&.id.nil? ? 'null' : game.id.to_i
      <<~TXT.strip
        SUBSTITUA o bloco JSON abaixo pelo JSON COMPLETO gerado no projeto (export do jogo):

        #{export_cmd}

        Chaves típicas no ficheiro exportado: export_version, season, game, team_season_stats, odds_snapshots, openai, players.
        O export pode já incluir "external_game_context" na raiz — a secção "external_game_context:" abaixo repete o snapshot curado para leitura rápida (pode ignorar a duplicata na raiz do JSON se preferir).

        #{placeholder_json_block(m, game_id_json)}
      TXT
    end

    def placeholder_json_block(m, game_id_json)
      <<~JSON.strip
        Placeholder (NÃO usar como dados reais — sem isto o modelo responde "sem dado no input" para EV):
        {
          "game": {
            "id": #{game_id_json},
            "hint": "#{m[:matchup_label]} — confirmar mandante vs ESPN (home = #{m[:home_abbr]})."
          },
          "players": [],
          "team_season_stats": { "home": {}, "away": {} },
          "odds_snapshots": [],
          "openai": { "user_message_prefix": "Dados JSON:\\n" }
        }
      JSON
    end

    def embed_export_json(game)
      return nil if ENV['PLAY_IN_SKIP_EMBEDDED_EXPORT'].to_s == '1'
      return nil unless game

      res = ::Ai::GamePayloadExporter.call(
        game_id: game.id,
        player_limit: ENV.fetch('AI_EXPORT_PLAYER_LIMIT', '20').to_i,
        output_path: nil
      )
      unless res.success?
        warn "[ai:play_in_openai_package] Export JSON falhou (game_id=#{game.id}): #{res.error}"
        return nil
      end

      j = res.json.to_s
      max = ENV['PLAY_IN_EMBED_EXPORT_MAX_CHARS'].to_i
      if max.positive? && j.bytesize > max
        j = j.byteslice(0, max) + "\n\n... [TRUNCADO — defina PLAY_IN_EMBED_EXPORT_MAX_CHARS=0 ou gere tmp/game_#{game.id}_ai_export.json]"
      end

      warn_empty_odds!(game.id, j)
      j
    end

    def warn_empty_odds!(game_id, json_text)
      h = JSON.parse(json_text)
      odds = h['odds_snapshots']
      return unless odds.is_a?(Array) && odds.empty?

      warn "[ai:play_in_openai_package] odds_snapshots vazio no export (game_id=#{game_id}). " \
           'Sem linhas/odds no DB o prompt de EV pode devolver PASS / lista vazia — importe odds ou anexe manualmente.'
    rescue JSON::ParserError
      nil
    end

    def optional_appendix(template_text, m, research_body, db_section)
      return '' unless appendix_enabled?

      buf = +''
      if template_text.present?
        part5 = part5_preamble(template_text) + extract_single_jogo_block(template_text, m[:index])
        part6 = template_from_part6(template_text)
        buf << section('APÊNDICE — Parte 5 (template) + checklist', part5 + "\n\n" + part6)
      else
        buf << section('APÊNDICE', "Aviso: #{TEMPLATE_REL} não encontrado — Parte 5/6 do template omitidas.\n")
      end
      buf << section('APÊNDICE — Estudo auxiliar completo', research_body)
      buf << section('APÊNDICE — Resolução no banco + export', db_section)
      buf
    end

    def part5_preamble(template)
      m = template.match(
        /PARTE 5 — CONTEXTO EXTERNO.*?^-{10,}\RAVISO:.*?\R\R(?=--- Jogo \d)/m
      )
      raise 'Template inesperado: preâmbulo da Parte 5 (use template completo ou PLAY_IN_PACKAGE_APPENDIX=0)' unless m

      m[0].sub(
        /PARTE 5 — CONTEXTO EXTERNO DOS 4 JOGOS PLAY-IN.*/,
        'PARTE 5 — CONTEXTO EXTERNO (RECORTE: SÓ ESTE JOGO)'
      )
    end

    def extract_single_jogo_block(template, jogo_index)
      re = /--- Jogo #{jogo_index} \|.*?(?=\R--- Jogo \d \||\R{2,}PARTE 6)/m
      block = template[re]
      raise "Template inesperado: bloco Jogo #{jogo_index}" if block.blank?

      block.strip + "\n"
    end

    def template_from_part6(template)
      i = template.index('PARTE 6 — CHECKLIST')
      raise 'Template inesperado: falta PARTE 6' unless i

      template[i..]
    end

    def section(title, body)
      s = []
      s << ''
      s << '=' * 80
      s << title
      s << '=' * 80
      s << body.to_s.rstrip
      s << ''
      s.join("\n")
    end

    def parse_optional_game_ids
      raw = ENV['PLAY_IN_GAME_IDS'].to_s.strip
      return nil if raw.blank?

      raw.split(',').map { |x| x.strip.to_i }.reject(&:zero?)
    end

    def parse_optional_date(key)
      raw = ENV[key].to_s.strip
      return nil if raw.blank?

      Date.iso8601(raw)
    rescue ArgumentError
      warn "Ignorando #{key} inválido: #{raw.inspect}"
      nil
    end

    def resolve_game(m, id_list, on_date)
      if id_list.present?
        gid = id_list[m[:index] - 1]
        return Game.find_by(id: gid) if gid.present?
      end

      scope = apply_play_in_date_scope(Game.all, on_date)
      matches = scope.to_a.select { |g| roster_match?(g, m[:home_abbr], m[:away_abbr]) }
      return nil if matches.empty?

      espn = m[:espn_game_id].to_s.presence
      if espn.present?
        by_espn = matches.select { |g| g.nba_game_id.to_s == espn }
        matches = by_espn if by_espn.size == 1
      end

      if matches.size > 1
        cand = matches.map { |g| "id=#{g.id} date=#{g.game_date} nba_game_id=#{g.nba_game_id.inspect}" }.join('; ')
        warn "[ai:play_in_openai_package] Vários jogos para #{m[:slug]} (#{matches.size}): #{cand}. " \
             'Escolhido o mais recente por game_date; use PLAY_IN_ON_DATE, PLAY_IN_GAME_IDS, ' \
             'PLAY_IN_DATE_FROM/TO, ou alinhar nba_game_id com espn_game_id no matchup.'
      end

      matches.max_by { |g| g.game_date || Date.jd(0) }
    end

    # Sem PLAY_IN_ON_DATE: restringe a uma janela típica de play-in (abril 2026) para evitar
    # duplicados da temporada regular com o mesmo mandante/visitante.
    def apply_play_in_date_scope(scope, on_date)
      if on_date
        return scope.where(game_date: on_date)
      end
      return scope if ENV['PLAY_IN_NO_DATE_FILTER'].present?

      from = parse_optional_date('PLAY_IN_DATE_FROM') || Date.new(2026, 4, 11)
      to   = parse_optional_date('PLAY_IN_DATE_TO')   || Date.new(2026, 4, 22)
      scope.where(game_date: from..to)
    end

    def date_filter_summary
      if ENV['PLAY_IN_ON_DATE'].present?
        "PLAY_IN_ON_DATE=#{ENV['PLAY_IN_ON_DATE']}"
      elsif ENV['PLAY_IN_NO_DATE_FILTER'].present?
        'nenhum (PLAY_IN_NO_DATE_FILTER=1)'
      else
        from = ENV['PLAY_IN_DATE_FROM'].presence || '2026-04-11 (default)'
        to   = ENV['PLAY_IN_DATE_TO'].presence   || '2026-04-22 (default)'
        "game_date em #{from}..#{to} (PLAY_IN_DATE_FROM/TO ou PLAY_IN_ON_DATE para afinar)"
      end
    end

    def roster_match?(game, expect_home, expect_away)
      r = GameRoster.new(game: game)
      r.home_abbr == expect_home && r.away_abbr == expect_away
    end

    def build_db_section(game, m)
      lines = []
      lines << 'Procurado no DB (GameRoster):'
      lines << "  home_abbr=#{m[:home_abbr]} away_abbr=#{m[:away_abbr]}"
      lines << "  filtro data: #{date_filter_summary}"
      lines << ''

      unless game
        lines << 'Nenhum registo único encontrado.'
        lines << 'Sugestão: defina PLAY_IN_GAME_IDS=id1,id2,id3,id4 (ordem dos 4 jogos) ou PLAY_IN_ON_DATE=AAAA-MM-DD.'
        lines << ''
        lines << build_export_command(nil)
        return lines.join("\n")
      end

      r = GameRoster.new(game: game)
      odds_n = OddsSnapshot.where(game_id: game.id).count
      lines << "Encontrado: id=#{game.id} game_date=#{game.game_date} status=#{game.status}"
      lines << "  home_team=#{game.home_team.inspect} away_team=#{game.away_team.inspect}"
      lines << "  normalizado: home=#{r.home_abbr} away=#{r.away_abbr}"
      lines << "  OddsSnapshot: #{odds_n}"
      lines << ''
      lines << build_export_command(game)
      lines.join("\n")
    end

    def build_export_command(game)
      gid = game&.id || '<GAME_ID>'
      <<~CMD.strip
        GAME_ID=#{gid} AI_EXPORT_PLAYER_LIMIT=#{ENV.fetch('AI_EXPORT_PLAYER_LIMIT', '20')} \\
          AI_EXPORT_OUT=tmp/game_#{gid}_ai_export.json \\
          bin/rails ai:export_game_payload
      CMD
    end
end

# Pacote “leve” só com contexto narrativo + prompt + placeholder de export (sem JSON pesado dos jogadores).
module PlayInContextSendPackage
  module_function

  def call
    root = Rails.root
    prompt_rel = ENV.fetch('PLAY_IN_SEND_PROMPT_REL', 'play_in_2026_research/prompts/play_in_portfolio_system_exact.txt')
    prompt_path = root.join(prompt_rel)
    raise "Prompt em falta: #{prompt_path}" unless prompt_path.file?

    prompt_body = prompt_path.read.rstrip
    out_dir = root.join(ENV.fetch('OUT_DIR', 'play_in_2026_research/generated_openai_packages'))
    FileUtils.mkdir_p(out_dir)

    id_list = PlayInOpenaiPackageGenerator.parse_optional_game_ids
    on_date = PlayInOpenaiPackageGenerator.parse_optional_date('PLAY_IN_ON_DATE')

    ::Ai::PlayIn2026Context::MATCHUPS.each do |m|
      game = PlayInOpenaiPackageGenerator.resolve_game(m, id_list, on_date)
      research_path = root.join('play_in_2026_research', m[:research])
      research_body = research_path.file? ? research_path.read : "(ficheiro em falta: #{m[:research]})\n"

      external = ::Ai::PlayIn2026Context.build_package_hash(m, game)
      export_cmd = PlayInOpenaiPackageGenerator.build_export_command(game)
      placeholder = export_placeholder_json(m, game, export_cmd)

      out_name = format('%02d_%s_send_context.txt', m[:index], m[:slug])
      doc = []
      doc << send_header(root, m, game, research_path, prompt_path, out_name)
      doc << PlayInOpenaiPackageGenerator.section('CONTEXTO AUXILIAR DO JOGO (estudo — mando, recorde, spread/total, líderes, lesões, notas)', research_body)
      doc << PlayInOpenaiPackageGenerator.section('RESUMO OPERACIONAL (snapshot curado)', operational_summary(m, external))
      doc << PlayInOpenaiPackageGenerator.section('SYSTEM / BASE DE ANÁLISE (copiar como system prompt)', prompt_body)
      doc << PlayInOpenaiPackageGenerator.section('USER — Dados JSON (PLACEHOLDER: substituir pelo export real)', JSON.pretty_generate(placeholder))
      doc << PlayInOpenaiPackageGenerator.section('USER — external_game_context (JSON)', JSON.pretty_generate(external))
      doc << PlayInOpenaiPackageGenerator.section('NOTAS', send_footer_notes(export_cmd))

      File.write(out_dir.join(out_name), doc.join("\n"))
      puts "Gerado → #{out_dir.join(out_name)}"
    end

    puts "Concluído (#{::Ai::PlayIn2026Context::MATCHUPS.size} ficheiros send_context em #{out_dir})."
  end

  def send_header(root, m, game, research_path, prompt_path, out_name)
    lines = []
    lines << '=' * 80
    lines << 'PACOTE PARA ENVIAR — PLAY-IN 2026 (contexto + prompt + placeholder de export)'
    lines << "Ficheiro: #{out_name}"
    lines << "Slug: #{m[:slug]} · Matchup: #{m[:matchup_label]}"
    lines << "Gerado em: #{Time.current.utc.iso8601} UTC"
    lines << "Estudo: #{research_path.relative_path_from(root)}"
    lines << "Prompt: #{prompt_path.relative_path_from(root)}"
    lines << "GAME_ID (opcional, para comando export): #{game ? game.id : 'não resolvido — defina PLAY_IN_GAME_IDS ou datas'}"
    lines << 'Este ficheiro NÃO inclui players/portfolio_input/markets_data — só o esqueleto; preencha com ai:export_game_payload.'
    lines << '=' * 80
    lines << ''
    lines.join("\n")
  end

  def operational_summary(m, external)
    ext = external.deep_stringify_keys
    book = ext['book'].is_a?(Hash) ? ext['book'].map { |k, v| "  • #{k}: #{v.inspect}" }.join("\n") : '  (sem book)'
    inj = Array(ext['injuries']).map { |h| "  • #{h['team']} #{h['player']}: #{h['status']} — #{h['reason']}" }.join("\n")
    elig = Array(ext['eligibility_notes']).map { |s| "  • #{s}" }.join("\n")
    nar = Array(ext['narrative_notes']).map { |s| "  • #{s}" }.join("\n")
    chk = Array(ext['checklist_reminders']).map { |s| "  • #{s}" }.join("\n")

    <<~TXT.strip
      Mandante (abrev. canónica): #{m[:home_abbr]} · Visitante: #{m[:away_abbr]}
      Torneio: #{ext['tournament']}
      Rótulo: #{ext['matchup_label']}
      Transmissão: #{ext['broadcast']}
      ESPN game id (quando existir): #{m[:espn_game_id].inspect}

      Book (snapshot textual / números no JSON abaixo):
      #{book}

      Lesões (lista):
      #{inj.presence || '  (sem linhas)'}

      Notas de elegibilidade / mandante:
      #{elig.presence || '  —'}

      Notas narrativas:
      #{nar.presence || '  —'}

      Checklist (prompt):
      #{chk.presence || '  —'}
    TXT
  end

  def export_placeholder_json(m, game, export_cmd)
    {
      instrucao: 'Substitua este objeto inteiro pelo JSON COMPLETO de Ai::GamePayloadExporter (players[].portfolio_input, markets_data, odds_snapshots, openai.system_prompts, etc.).',
      comando: export_cmd,
      export_version: 1,
      season: '2025-26',
      generated_at: nil,
      game: {
        id: game&.id,
        game_date: game&.game_date&.to_s,
        home_team: "(confirmar string do DB — mandante deve ser #{m[:home_abbr]} na ESPN)",
        away_team: "(visitante #{m[:away_abbr]})",
        normalized_home_abbr: m[:home_abbr],
        normalized_away_abbr: m[:away_abbr],
        status: nil
      },
      team_season_stats: {
        home: { team_abbr: m[:home_abbr], synced: false, nota: 'preenchido no export' },
        away: { team_abbr: m[:away_abbr], synced: false, nota: 'preenchido no export' }
      },
      odds_snapshots: [],
      openai: {
        user_message_prefix: 'Dados JSON:\n',
        nota: 'No export real, openai inclui system_prompts completos.'
      },
      players: []
    }
  end

  def send_footer_notes(export_cmd)
    <<~TXT.strip
      1) Cole primeiro o SYSTEM, depois a mensagem USER com o JSON real no lugar do placeholder.
      2) Mantenha external_game_context; alinhe com o export (pode haver duplicata na raiz do export — use uma versão só).
      3) Sem odds_snapshots no export, EV vs casa pode ficar "sem dado no input".
      4) Para gerar o JSON pesado:
      #{export_cmd}
    TXT
  end
end
