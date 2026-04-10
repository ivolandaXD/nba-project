namespace :nba do
  desc "Importa elenco da NBA (commonallplayers) e preenche players.nba_player_id; tenta vincular jogadores existentes sem ID (nome + time, match único)"
  task sync_league_players: :environment do
    season = Nba::Season.current
    puts "Temporada (roster): #{season}"
    result = NbaStats::LeaguePlayersSync.call(season: season)
    puts "Catálogo: #{result.upserted_count} linha(s) gravadas (find_or_initialize por nba_player_id)."
    puts "Vínculos: #{result.linked_orphans_count} jogador(es) sem ID receberam nba_player_id (nome+time único)."
    if result.errors.any?
      puts "Erros (#{result.errors.size}):"
      result.errors.first(50).each { |e| puts "  #{e}" }
    end
    puts result.success? ? 'Concluído.' : 'Concluído com erros (veja acima).'
  end

  desc "Sincroniza player_season_stats para todos os jogadores com nba_player_id (temporada NBA_SEASON / Nba::Season.current)"
  task sync_season_stats: :environment do
    season = Nba::Season.current
    puts "Temporada: #{season}"
    total = Player.count
    with_id = Player.where.not(nba_player_id: nil).count
    with_bdl = Player.where.not(bdl_player_id: nil).count
    puts "Jogadores no banco: #{total} · com nba_player_id: #{with_id} · com bdl_player_id: #{with_bdl}"
    if with_id.zero?
      puts 'Nenhum jogador com NBA ID — a importação de temporada não fará chamadas à API.'
      puts 'Rode antes: bin/rails nba:sync_league_players'
      puts '(ou preencha nba_player_id manualmente / via outro fluxo).'
    end

    result = NbaStats::PlayerSeasonStatsSync.call(season: season, limit: nil)
    puts "OK: #{result.synced_count} jogador(es) com estatísticas de temporada atualizadas."
    puts "Erros (#{result.errors.size}):", *result.errors.first(50) if result.errors.any?
  end

  desc "Roster da NBA (commonallplayers) + playercareerstats para todos com nba_player_id"
  task sync_season_full: :environment do
    Rake::Task['nba:sync_league_players'].invoke
    puts ''
    Rake::Task['nba:sync_season_stats'].invoke
  end

  desc "Médias por jogo da liga por time (stats.nba.com leaguedashteamstats) → team_season_stats"
  task sync_team_season_stats: :environment do
    season = Nba::Season.current
    puts "Temporada: #{season}"
    result = NbaStats::TeamSeasonStatsSync.call(season: season)
    puts "Times: #{result.synced_count} linha(s)."
    puts "Erros (#{result.errors.size}):", *result.errors.first(30) if result.errors.any?
  end

  desc "Reconstrói player_opponent_splits a partir de player_game_stats (intervalo Nba::Season.date_range_for)"
  task rebuild_player_opponent_splits: :environment do
    season = Nba::Season.current
    puts "Temporada: #{season} · intervalo #{Nba::Season.date_range_for(season)}"
    result = NbaStats::PlayerOpponentSplitsRebuild.call(season: season)
    if result.success?
      puts "OK: #{result.rows_upserted} linha(s) (jogador × adversário)."
      if result.pgs_processed
        puts "     player_game_stats processados: #{result.pgs_processed} · sem adversário resolvido: #{result.skipped_no_opp}"
      end
    else
      puts "Erro: #{result.error}"
    end
  end

  desc "Dados agregados para IA: times (liga) + splits jogador×adversário (requer game logs no banco)"
  task sync_context_for_ai: :environment do
    Rake::Task['nba:sync_team_season_stats'].invoke
    puts ''
    Rake::Task['nba:rebuild_player_opponent_splits'].invoke
  end

  desc <<-DESC.squish
    Importa o GAME LOG por jogador (stats.nba.com playergamelog → fallback balldontlie): uma linha em
    player_game_stats POR PARTIDA da temporada regular (PTS, REB, MIN, adversário, casa/fora, etc.),
    vinculada ao player_id e ao game_id (games.nba_game_id = Game_ID da NBA). Não são médias da temporada
    (isso é player_season_stats). Um jogador com ~60 linhas ≈ ~60 jogos importados para ele. ENV:
    NBA_GAMELOG_SYNC_LIMIT, NBA_GAMELOG_START_OFFSET, NBA_GAMELOG_DELAY_SEC (default 0.5). Alternativa: data_sync/ (Python).
  DESC
  task sync_all_player_game_logs: :environment do
    season = Nba::Season.current
    delay = ENV.fetch('NBA_GAMELOG_DELAY_SEC', 0.5).to_f
    limit = ENV['NBA_GAMELOG_SYNC_LIMIT'].presence&.to_i
    offset = ENV.fetch('NBA_GAMELOG_START_OFFSET', 0).to_i

    base = Player.where('nba_player_id IS NOT NULL OR bdl_player_id IS NOT NULL').order(:id)
    eligible = base.count
    queued = base
    queued = queued.offset(offset) if offset.positive?
    queued = queued.limit(limit) if limit.present? && limit.positive?
    players = queued.to_a
    total_run = players.size

    puts "=== NBA game logs · temporada #{season} ==="
    puts "Elegíveis no banco: #{eligible} · nesta execução: #{total_run} (offset #{offset}#{limit.present? && limit.positive? ? ", limite #{limit}" : ''})"
    puts "Pausa entre jogadores: #{delay}s · delay ajustável com NBA_GAMELOG_DELAY_SEC"
    puts ''
    players.each_with_index do |player, idx|
      done = idx + 1
      remaining = total_run - done
      puts "[#{done}/#{total_run}] (faltam #{remaining}) #{player.name} (#{player.team}) · NBA ID: #{player.nba_player_id || '—'} · BDL: #{player.bdl_player_id || '—'}"
      r = NbaStats::PlayerGameLogImporter.call(player, season: season)
      err = r.error.present? ? " · erro: #{r.error}" : ''
      puts "         → linhas: #{r.stats_count} · fonte: #{r.source || '—'} · ok=#{r.success?}#{err}"
      sleep(delay) if delay.positive?
    end

    puts ''
    puts 'Concluído. Rode depois: bin/rails nba:sync_context_for_ai (times + splits) e confira a Central de Dados na web.'
  end

  desc "Relatório: histórico de game logs, player_opponent_splits e cobertura de team_season_stats (30 franquias)"
  task validate_data_readiness: :environment do
    season = Nba::Season.current
    range = Nba::Season.date_range_for(season)
    expected = NbaStats::TeamCodes::ALL

    def pct(num, den)
      den.zero? ? 0.0 : (100.0 * num / den)
    end

    puts '=== nba:validate_data_readiness ==='
    puts "Temporada: #{season}"
    puts "Intervalo usado em opponent_splits (games.game_date): #{range&.begin} .. #{range&.end}"
    puts ''

    # --- 1) Game log history ---
    pgs_total = PlayerGameStat.count
    with_nba = Player.where.not(nba_player_id: nil).count
    with_bdl = Player.where.not(bdl_player_id: nil).count
    gp_by_player = PlayerGameStat.group(:player_id).count
    vals = gp_by_player.values
    n_with_log = gp_by_player.size

    puts '--- 1) Jogadores têm histórico suficiente? (player_game_stats) ---'
    puts "Linhas totais: #{pgs_total}"
    puts "Jogadores com nba_player_id: #{with_nba} · com bdl_player_id: #{with_bdl}"
    puts "Jogadores distintos com ≥1 linha de log: #{n_with_log}"

    if vals.empty?
      puts 'VEREDITO: NÃO — sem game logs no banco. Rode nba:sync_all_player_game_logs (ou Python data_sync).'
    else
      sorted = vals.sort
      mid = sorted.size / 2
      median = sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
      mean = (sorted.sum.to_f / sorted.size).round(2)
      puts "Por jogador (só quem tem log): min=#{sorted.first} mediana≈#{median} max=#{sorted.last} média=#{mean}"
      [5, 10, 20, 41].each do |g|
        c = vals.count { |v| v >= g }
        puts "  ≥ #{g} jogos: #{c} (#{pct(c, n_with_log).round(1)}% dos com log)"
      end

      if range
        in_window = PlayerGameStat.joins(:game).where(games: { game_date: range }).count
        pl_window = PlayerGameStat.joins(:game).where(games: { game_date: range }).distinct.count(:player_id)
        puts "No intervalo da temporada (join games): #{in_window} linhas · #{pl_window} jogadores"
        puts (in_window < 100 ? 'VEREDITO: FRACO — poucos logs na janela da temporada (métricas L5/L10 e splits sofrem).' : 'VEREDITO: OK parcial — há volume na janela; ajuste o limiar conforme seu uso.')
      end
    end

    puts ''
    puts '--- 2) opponent_splits estão preenchidos? ---'
    split_rows = PlayerOpponentSplit.where(season: season).count
    split_players = PlayerOpponentSplit.where(season: season).distinct.count(:player_id)
    puts "Linhas (season=#{season}): #{split_rows} · jogadores com ≥1 split: #{split_players}"
    if split_rows.zero?
      puts 'VEREDITO: NÃO — vazio. Rode nba:rebuild_player_opponent_splits ou nba:sync_context_for_ai.'
      puts '        O rebuild usa opponent_team; se vazio, infere pelo jogo (is_home + home_team/away_team) e pelo players.team.'
    elsif split_rows < 50
      puts 'VEREDITO: FRACO — poucas linhas; confira se game logs cobrem a temporada e opponent_team nas linhas.'
    else
      puts 'VEREDITO: OK — há dados agregados (volume absoluto depende do elenco importado).'
    end

    puts ''
    puts '--- 3) team_season_stats existe para todos os times? ---'
    abbrs = TeamSeasonStat.where(season: season).distinct.pluck(:team_abbr).map { |a| a.to_s.upcase.strip }.compact.uniq.sort
    missing = expected - abbrs
    extra = abbrs - expected
    ts_count = TeamSeasonStat.where(season: season).count
    pace_ok = TeamSeasonStat.where(season: season).where.not(pace: nil).count
    puts "Times distintos: #{abbrs.size}/#{expected.size} · registros na tabela: #{ts_count} · com pace: #{pace_ok}"
    if missing.any?
      puts "Faltando (#{missing.size}): #{missing.join(', ')}"
      puts 'VEREDITO: NÃO completo — rode nba:sync_team_season_stats ou nba:sync_context_for_ai.'
    else
      puts 'VEREDITO: OK — 30 franquias presentes (abbr alinhada à lista interna).'
    end
    puts "Abreviações fora da lista padrão: #{extra.join(', ')}" if extra.any?
    puts ''
    puts 'Próximo passo se algo falhar: Central de Dados (web) + nba:sync_context_for_ai'
  end
end
