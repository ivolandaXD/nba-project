# frozen_string_literal: true

namespace :nba do
  desc 'Importa os bilhetes (CHA x DET, 10/04/2026) como placed_ai_suggestions para o usuário ADMIN_EMAIL'
  task import_cha_det_apr10_placed_suggestions: :environment do
    user, email = PlacedAiSuggestionsImport.import_user!

    game = PlacedAiSuggestionsImport.find_det_at_cha_game(Date.new(2026, 4, 10))
    raise 'Jogo DET @ CHA em 2026-04-10 não encontrado (sincronize a grade ou ajuste a data no rake).' unless game

    n = PlacedAiSuggestionsImport.seed_rows!(
      user: user,
      rows: PlacedAiSuggestionsImport.cha_det_rows.map { |r| r.merge(game: game) }
    )
    puts "Importadas/atualizadas #{n} sugestão(ões) para jogo ##{game.id} (#{game.away_team} @ #{game.home_team})."
  end

  desc 'Importa bilhetes extras do dia 10/04/2026 (DEN/OKC, HOU/MIN, CHI/ORL, ATL/CLE, WAS/MIA, duplas e tripla)'
  task import_apr10_extra_placed_suggestions: :environment do
    user, email = PlacedAiSuggestionsImport.import_user!

    d = Date.new(2026, 4, 10)
    rows = PlacedAiSuggestionsImport.april10_extra_rows(d)
    n = PlacedAiSuggestionsImport.seed_rows!(user: user, rows: rows)
    missing = rows.select { |r| r[:game].nil? && r[:slip_kind] == 'parlay' }.map { |r| r[:external_bet_id] }
    puts "Importadas/atualizadas #{n} sugestão(ões) (IDs externos novos ou existentes)."
    if missing.any?
      puts "Aviso: estes bilhetes ficaram sem game_id (jogo não encontrado no DB para #{d}): #{missing.join(', ')} — aparecem na Central de IA em «multi-jogo»."
    end
  end

  desc 'Importa simples + 3 múltiplas LAC x GSW (prints 12/04/2026); legs só player/market/line. USER_EMAIL opcional; default db/seeds.rb. GAME_ID / NBA_LAC_GSW_DATE'
  task import_lac_gsw_apr12_placed_suggestions: :environment do
    user, email = PlacedAiSuggestionsImport.import_user!

    game_id = ENV['GAME_ID'].presence
    date =
      if ENV['NBA_LAC_GSW_DATE'].present?
        Date.parse(ENV['NBA_LAC_GSW_DATE'])
      else
        Date.new(2026, 4, 12)
      end

    game = PlacedAiSuggestionsImport.find_lac_gsw_game(date, game_id: game_id)
    raise "Jogo LAC x GSW em #{date} não encontrado (use GAME_ID=1229 ou sincronize a grade)." unless game

    rows = PlacedAiSuggestionsImport.lac_gsw_apr12_rows(game: game)
    n = PlacedAiSuggestionsImport.seed_rows!(user: user, rows: rows)
    puts "Utilizador: #{email}"
    puts "Importadas/atualizadas #{n} sugestão(ões) para jogo ##{game.id} (#{game.away_team} @ #{game.home_team})."
  end

  desc 'Atualiza resultados (win/loss) dos bilhetes LAC×GSW (12/04/2026) pelos prints de fecho; opcional SYNC_LEGS=1 para resync+settlement das pernas. USER_EMAIL como nos imports.'
  task set_lac_gsw_apr12_placed_suggestion_results: :environment do
    user, email = PlacedAiSuggestionsImport.import_user!
    puts "Utilizador: #{email}"
    PlacedAiSuggestionsResultsLacGswApr12.apply!(user, sync_legs: ENV['SYNC_LEGS'].present?)
  end

  desc 'Atualiza resultados (win / loss / void) dos bilhetes com IDs conhecidos — fechamento 10–12/04/2026 (prints)'
  task set_apr10_2026_placed_suggestion_results: :environment do
    user, email = PlacedAiSuggestionsImport.import_user!

    PlacedAiSuggestionsResultsApr2026.apply!(user)
  end
end

# Dados extraídos dos bilhetes (abr/2026).
module PlacedAiSuggestionsImport
  module_function

  # Mesmo contrato que db/seeds.rb: `ENV.fetch('ADMIN_EMAIL', 'admin@example.com')`.
  # Sem USER_EMAIL válido, usa esse admin. Se USER_EMAIL estiver definido mas não existir, faz fallback ao admin do seed (com aviso).
  def import_user!
    seeds_email = ENV.fetch('ADMIN_EMAIL', 'admin@example.com')
    requested = ENV['USER_EMAIL'].presence || seeds_email
    user = User.find_by(email: requested)

    if user.nil? && ENV['USER_EMAIL'].present? && requested != seeds_email
      warn "[nba:placed_ai_suggestions] USER_EMAIL=#{requested.inspect} não existe em users; a usar o admin de db/seeds.rb: #{seeds_email}"
      user = User.find_by(email: seeds_email)
      requested = seeds_email if user
    end

    unless user
      raise <<~MSG.squish
        User não encontrado para #{requested.inspect}.
        db/seeds.rb cria o admin com `ENV.fetch('ADMIN_EMAIL', 'admin@example.com')`.
        Rode `bin/rails db:seed` ou defina `USER_EMAIL` para um email existente.
        Para o default do seed, não defina `USER_EMAIL` (ou use ADMIN_EMAIL igual ao seed).
      MSG
    end

    [user, requested]
  end

  def seed_rows!(user:, rows:)
    count = 0
    rows.each do |row|
      seed_one!(user: user, row: row)
      count += 1
    end
    count
  end

  def seed_one!(user:, row:)
    rec = PlacedAiSuggestion.find_or_initialize_by(user: user, external_bet_id: row[:external_bet_id])
    rec.assign_attributes(
      game: row[:game],
      slip_kind: row[:slip_kind],
      description: row[:description],
      legs: row[:legs],
      decimal_odds: row[:decimal_odds],
      stake_brl: row[:stake_brl],
      result: rec.new_record? ? 'pending' : rec.result
    )
    rec.save!
    rec
  end

  def find_det_at_cha_game(date)
    scope = Game.where(game_date: date)
    found = scope.find_by(home_team: 'CHA', away_team: 'DET')
    return found if found

    scope.where('home_team ILIKE ? AND away_team ILIKE ?', '%Charlotte%', '%Detroit%').first
  end

  # LAC (casa) x Golden State — placar pode vir como GS ou GSW.
  def find_lac_gsw_game(date, game_id: nil)
    return Game.find_by(id: game_id.to_i) if game_id.present?

    scope = Game.where(game_date: date)
    %w[GS GSW].each do |away|
      g = scope.find_by(home_team: 'LAC', away_team: away)
      return g if g
    end

    scope.where(home_team: 'LAC').where('away_team ILIKE ? OR away_team ILIKE ?', '%GS%', '%Golden%').first
  end

  # Perna mínima alinhada a PlacedAiSuggestion: só `player`, `market`, `line` (linha X.5 = "N+" over).
  def lac_gsw_leg(player, market, line)
    { 'player' => player, 'market' => market, 'line' => line.to_s }
  end

  # Simples (IDs dos prints) + 3 múltiplas reais (Criar Aposta, prints 12/04/2026). `game_id` no bilhete resolve o jogo nas pernas.
  def lac_gsw_apr12_rows(game:)
    pts = 'Total de pontos'
    reb = 'Total de rebotes'
    thr = 'Arremessos de três convertidos'
    thr_print = 'Arremessos de três pontos convertidos' # texto do print (SGP); normalizador aceita ambos
    blk = 'Tocos'
    leg_fn = method(:lac_gsw_leg)

    singles = [
      {
        external_bet_id: '9711558175',
        slip_kind: 'single',
        game: game,
        description: 'Gui Santos — Arremessos de três convertidos 2+ (@2,80)',
        decimal_odds: 2.80,
        stake_brl: 1.0,
        legs: [leg_fn.call('Gui Santos', thr, '1.5')]
      },
      {
        external_bet_id: '9711557419',
        slip_kind: 'single',
        game: game,
        description: 'Stephen Curry — Arremessos de três convertidos 4+ (@1,60)',
        decimal_odds: 1.60,
        stake_brl: 1.0,
        legs: [leg_fn.call('Stephen Curry', thr, '3.5')]
      },
      {
        external_bet_id: '9711553741',
        slip_kind: 'single',
        game: game,
        description: 'Brook Lopez — Tocos 1+ (@1,25)',
        decimal_odds: 1.25,
        stake_brl: 1.0,
        legs: [leg_fn.call('Brook Lopez', blk, '0.5')]
      },
      {
        external_bet_id: '9711551526',
        slip_kind: 'single',
        game: game,
        description: 'Al Horford — Total de rebotes 5+ (@1,88)',
        decimal_odds: 1.88,
        stake_brl: 1.0,
        legs: [leg_fn.call('Al Horford', reb, '4.5')]
      },
      {
        external_bet_id: '9711550838',
        slip_kind: 'single',
        game: game,
        description: 'Brandin Podziemski — Total de rebotes 5+ (@2,05)',
        decimal_odds: 2.05,
        stake_brl: 1.0,
        legs: [leg_fn.call('Brandin Podziemski', reb, '4.5')]
      },
      {
        external_bet_id: '9711547595',
        slip_kind: 'single',
        game: game,
        description: 'Brandin Podziemski — Total de pontos 13+ (@1,90)',
        decimal_odds: 1.90,
        stake_brl: 1.0,
        legs: [leg_fn.call('Brandin Podziemski', pts, '12.5')]
      },
      {
        external_bet_id: '9711546560',
        slip_kind: 'single',
        game: game,
        description: 'Kristaps Porziņģis — Total de pontos 15+ (@2,55)',
        decimal_odds: 2.55,
        stake_brl: 1.0,
        legs: [leg_fn.call('Kristaps Porziņģis', pts, '14.5')]
      },
      {
        external_bet_id: '9711545229',
        slip_kind: 'single',
        game: game,
        description: 'Gui Santos — Total de pontos 10+ (@1,90)',
        decimal_odds: 1.90,
        stake_brl: 1.0,
        legs: [leg_fn.call('Gui Santos', pts, '9.5')]
      },
      {
        external_bet_id: '9711544744',
        slip_kind: 'single',
        game: game,
        description: 'Stephen Curry — Total de pontos 24+ (@2,18)',
        decimal_odds: 2.18,
        stake_brl: 1.0,
        legs: [leg_fn.call('Stephen Curry', pts, '23.5')]
      }
    ]

    # Múltiplas colocadas (prints): 2× tripla + 1× dupla — `slip_kind` = tripla | dupla conforme nº de pernas.
    multiples = [
      {
        external_bet_id: 'LACGSW-SGP-20260412-TRI-580',
        slip_kind: 'tripla',
        game: game,
        description: 'Criar aposta LAC×GSW — Stephen Curry 24+ PTS + Stephen Curry 4+ triplos + Brandin Podziemski 5+ rebotes (@5,80)',
        decimal_odds: 5.80,
        stake_brl: 1.0,
        legs: [
          leg_fn.call('Stephen Curry', pts, '23.5'),
          leg_fn.call('Stephen Curry', thr_print, '3.5'),
          leg_fn.call('Brandin Podziemski', reb, '4.5')
        ]
      },
      {
        external_bet_id: 'LACGSW-SGP-20260412-DUP-310',
        slip_kind: 'dupla',
        game: game,
        description: 'Criar aposta LAC×GSW — Gui Santos 10+ PTS + Gui Santos 2+ triplos (@3,10)',
        decimal_odds: 3.10,
        stake_brl: 1.0,
        legs: [
          leg_fn.call('Gui Santos', pts, '9.5'),
          leg_fn.call('Gui Santos', thr_print, '1.5')
        ]
      },
      {
        external_bet_id: 'LACGSW-SGP-20260412-TRI-900',
        slip_kind: 'tripla',
        game: game,
        description: 'Criar aposta LAC×GSW — Gui Santos 2+ triplos + Brandin Podziemski 5+ rebotes + Brandin Podziemski 13+ PTS (@9,00)',
        decimal_odds: 9.00,
        stake_brl: 1.0,
        legs: [
          leg_fn.call('Gui Santos', thr_print, '1.5'),
          leg_fn.call('Brandin Podziemski', reb, '4.5'),
          leg_fn.call('Brandin Podziemski', pts, '12.5')
        ]
      }
    ]

    singles + multiples
  end

  # Tenta vários pares (visitante LIKE, casa LIKE) para achar o jogo na data.
  def find_game_by_matchup(date, pairs)
    pairs.each do |away_like, home_like|
      g = Game.where(game_date: date).where('away_team ILIKE ? AND home_team ILIKE ?', away_like, home_like).first
      return g if g
    end
    nil
  end

  def april10_extra_rows(date)
    g_den_okc = find_game_by_matchup(
      date,
      [
        ['%Nuggets%', '%Thunder%'],
        ['%Nugget%', '%Thunder%'],
        ['%Denver%', '%Oklahoma%'],
        ['DEN', 'OKC']
      ]
    )
    g_chi_orl = find_game_by_matchup(
      date,
      [
        ['%Bulls%', '%Magic%'],
        ['CHI', 'ORL']
      ]
    )
    g_atl_cle = find_game_by_matchup(
      date,
      [
        ['%Hawks%', '%Cavaliers%'],
        ['%Hawks%', '%Cavs%'],
        ['ATL', 'CLE']
      ]
    )
    den = 'Denver Nuggets @ Oklahoma City Thunder'
    hou = 'Houston Rockets @ Minnesota Timberwolves'

    [
      dupla_9690916516(den, hou),
      dupla_9690914674(den, hou),
      parlay_den_okc_9690899997(g_den_okc),
      parlay_chi_orl_9690870848(g_chi_orl),
      tripla_9690852171,
      parlay_atl_cle_9690814132(g_atl_cle)
    ]
  end

  def dupla_9690916516(den_label, hou_label)
    {
      external_bet_id: '9690916516',
      slip_kind: 'dupla',
      game: nil,
      description: "Dupla · odds totais 13,50 — Criar aposta #{den_label} (@2,70) + Criar aposta #{hou_label} (@5,00)",
      decimal_odds: 13.5,
      stake_brl: 1.0,
      legs: [
        { 'event' => den_label, 'player' => 'Cameron Johnson', 'market' => 'Arremessos de três convertidos', 'line' => '2+' },
        { 'event' => den_label, 'player' => 'Nikola Jokic', 'market' => 'Total de assistências', 'line' => '10+' },
        { 'event' => den_label, 'player' => 'Cameron Johnson', 'market' => 'Total de pontos', 'line' => '12+' },
        { 'event' => hou_label, 'player' => 'Kevin Durant', 'market' => 'Total de pontos', 'line' => '23+' },
        { 'event' => hou_label, 'player' => 'Tari Eason', 'market' => 'Total de rebotes', 'line' => '6+' },
        { 'event' => hou_label, 'player' => 'Anthony Edwards', 'market' => 'Arremessos de três convertidos', 'line' => '3+' }
      ]
    }
  end

  def dupla_9690914674(den_label, hou_label)
    {
      external_bet_id: '9690914674',
      slip_kind: 'dupla',
      game: nil,
      description: "Dupla · odds totais 33,75 — Criar aposta #{den_label} (@2,70) + Criar aposta #{hou_label} (@12,50)",
      decimal_odds: 33.75,
      stake_brl: 1.0,
      legs: [
        { 'event' => den_label, 'player' => 'Cameron Johnson', 'market' => 'Arremessos de três convertidos', 'line' => '2+' },
        { 'event' => den_label, 'player' => 'Nikola Jokic', 'market' => 'Total de assistências', 'line' => '10+' },
        { 'event' => den_label, 'player' => 'Cameron Johnson', 'market' => 'Total de pontos', 'line' => '12+' },
        { 'event' => hou_label, 'player' => 'Kevin Durant', 'market' => 'Total de pontos', 'line' => '23+' },
        { 'event' => hou_label, 'player' => 'Tari Eason', 'market' => 'Total de rebotes', 'line' => '6+' },
        { 'event' => hou_label, 'player' => 'Anthony Edwards', 'market' => 'Total de assistências', 'line' => '3+' },
        { 'event' => hou_label, 'player' => 'Anthony Edwards', 'market' => 'Arremessos de três convertidos', 'line' => '3+' },
        { 'event' => hou_label, 'player' => 'Donte DiVincenzo', 'market' => 'Arremessos de três convertidos', 'line' => '3+' }
      ]
    }
  end

  def parlay_den_okc_9690899997(game)
    {
      external_bet_id: '9690899997',
      slip_kind: 'parlay',
      game: game,
      description: 'Criar aposta — Denver Nuggets @ Oklahoma City Thunder (@7,00)',
      decimal_odds: 7.0,
      stake_brl: 1.0,
      legs: [
        { 'player' => 'Cameron Johnson', 'market' => 'Arremessos de três convertidos', 'line' => '2+' },
        { 'player' => 'Jamal Murray', 'market' => 'Arremessos de três convertidos', 'line' => '3+' },
        { 'player' => 'Nikola Jokic', 'market' => 'Total de assistências', 'line' => '10+' },
        { 'player' => 'Nikola Jokic', 'market' => 'Total de rebotes', 'line' => '12+' },
        { 'player' => 'Cameron Johnson', 'market' => 'Total de pontos', 'line' => '12+' },
        { 'player' => 'Jamal Murray', 'market' => 'Total de pontos', 'line' => '21+' }
      ]
    }
  end

  def parlay_chi_orl_9690870848(game)
    {
      external_bet_id: '9690870848',
      slip_kind: 'parlay',
      game: game,
      description: 'Criar aposta — Chicago Bulls @ Orlando Magic (@4,45)',
      decimal_odds: 4.45,
      stake_brl: 1.0,
      legs: [
        { 'player' => 'Matas Buzelis', 'market' => 'Total de rebotes', 'line' => '6+' },
        { 'player' => 'Tre Jones', 'market' => 'Total de assistências', 'line' => '6+' },
        { 'player' => 'Jalen Suggs', 'market' => 'Arremessos de três convertidos', 'line' => '2+' }
      ]
    }
  end

  def tripla_9690852171
    atl = 'Atlanta Hawks @ Cleveland Cavaliers'
    cha = 'Charlotte Hornets @ Detroit Pistons'
    was = 'Washington Wizards @ Miami Heat'
    {
      external_bet_id: '9690852171',
      slip_kind: 'tripla',
      game: nil,
      description: 'Tripla · odds totais 16,63 — três Criar aposta (@2,40 · @2,20 · @3,15)',
      decimal_odds: 16.63,
      stake_brl: 1.0,
      legs: [
        { 'event' => atl, 'player' => 'Evan Mobley', 'market' => 'Total de assistências', 'line' => '3+' },
        { 'event' => atl, 'player' => 'Jalen Johnson', 'market' => 'Total de rebotes', 'line' => '9+' },
        { 'event' => cha, 'player' => 'Duncan Robinson', 'market' => 'Arremessos de três convertidos', 'line' => '2+' },
        { 'event' => cha, 'player' => 'LaMelo Ball', 'market' => 'Total de assistências', 'line' => '6+' },
        { 'event' => cha, 'player' => 'Duncan Robinson', 'market' => 'Total de pontos', 'line' => '9+' },
        { 'event' => was, 'player' => 'Bam Adebayo', 'market' => 'Total de rebotes', 'line' => '10+' },
        { 'event' => was, 'player' => 'Bilal Coulibaly', 'market' => 'Total de pontos', 'line' => '12+' }
      ]
    }
  end

  def parlay_atl_cle_9690814132(game)
    {
      external_bet_id: '9690814132',
      slip_kind: 'parlay',
      game: game,
      description: 'Criar aposta — Atlanta Hawks @ Cleveland Cavaliers (@2,92)',
      decimal_odds: 2.92,
      stake_brl: 1.0,
      legs: [
        { 'player' => 'Jalen Johnson', 'market' => 'Total de rebotes', 'line' => '10+' },
        { 'player' => 'Evan Mobley', 'market' => 'Total de assistências', 'line' => '3+' }
      ]
    }
  end

  def cha_det_rows
    [
      {
        external_bet_id: '9690707045',
        slip_kind: 'parlay',
        description: 'Criar aposta (mesmo jogo) — Duncan Robinson 2+ triplos + Jalen Duren 10+ rebotes',
        legs: [
          { 'player' => 'Duncan Robinson', 'market' => 'Arremessos de três convertidos', 'line' => '2+' },
          { 'player' => 'Jalen Duren', 'market' => 'Total de rebotes', 'line' => '10+' }
        ],
        decimal_odds: 2.85,
        stake_brl: 1.0
      },
      {
        external_bet_id: '9690708581',
        slip_kind: 'single',
        description: 'Duncan Robinson — Arremessos de três convertidos 2+',
        legs: [],
        decimal_odds: 1.38,
        stake_brl: 1.0
      },
      {
        external_bet_id: '9690710544',
        slip_kind: 'single',
        description: 'Moussa Diabaté — Total de rebotes 8+',
        legs: [],
        decimal_odds: 1.33,
        stake_brl: 1.0
      },
      {
        external_bet_id: '9690712035',
        slip_kind: 'single',
        description: 'Jalen Duren — Total de rebotes 10+',
        legs: [],
        decimal_odds: 2.05,
        stake_brl: 1.0
      },
      {
        external_bet_id: '9690714406',
        slip_kind: 'single',
        description: 'LaMelo Ball — Total de assistências 6+',
        legs: [],
        decimal_odds: 1.25,
        stake_brl: 1.0
      },
      {
        external_bet_id: '9690717600',
        slip_kind: 'single',
        description: 'Cade Cunningham — Total de assistências 8+',
        legs: [],
        decimal_odds: 1.60,
        stake_brl: 1.0
      },
      {
        external_bet_id: '9690724623',
        slip_kind: 'single',
        description: 'Jalen Duren — Total de pontos 16+',
        legs: [],
        decimal_odds: 1.45,
        stake_brl: 1.0
      },
      {
        external_bet_id: '9690726171',
        slip_kind: 'single',
        description: 'Miles Bridges — Total de pontos 15+',
        legs: [],
        decimal_odds: 1.75,
        stake_brl: 1.0
      },
      {
        external_bet_id: '9690727775',
        slip_kind: 'single',
        description: 'Brandon Miller — Total de pontos 17+',
        legs: [],
        decimal_odds: 1.25,
        stake_brl: 1.0
      }
    ]
  end
end

# LAC × GSW (2026-04-12): fecho pelos prints (simples = ID da casa; múltiplas = chaves LACGSW-SGP-* do import).
module PlacedAiSuggestionsResultsLacGswApr12
  module_function

  ID_TO_RESULT = {
    # Simples
    '9711558175' => 'loss',   # Gui Santos 2+ triplos — Perdida
    '9711557419' => 'win',    # Stephen Curry 4+ triplos — Ganhou
    '9711553741' => 'loss',   # Brook Lopez 1+ tocos — Perdida
    '9711551526' => 'loss',   # Al Horford 5+ rebotes — Perdida
    '9711550838' => 'loss',   # Brandin Podziemski 5+ rebotes — Perdida
    '9711547595' => 'loss',   # Brandin Podziemski 13+ PTS — Perdida
    '9711546560' => 'loss',   # Kristaps Porziņģis 15+ PTS — Perdida
    '9711545229' => 'loss',   # Gui Santos 10+ PTS — Perdida
    '9711544744' => 'win',    # Stephen Curry 24+ PTS — Ganhou
    # Múltiplas (external_bet_id do rake import_lac_gsw_apr12_placed_suggestions)
    'LACGSW-SGP-20260412-TRI-580' => 'loss', # tripla @5,80 — Perdida (ex.: 5+ REB Podz)
    'LACGSW-SGP-20260412-DUP-310' => 'loss', # dupla Gui @3,10 — Perdida
    'LACGSW-SGP-20260412-TRI-900' => 'loss'  # tripla @9,00 — Perdida
  }.freeze

  def apply!(user, sync_legs: false)
    updated = 0
    missing = []
    ID_TO_RESULT.each do |ext_id, res|
      rec = user.placed_ai_suggestions.find_by(external_bet_id: ext_id)
      if rec
        rec.update!(result: res)
        if sync_legs
          begin
            rec.resync_legs!
          rescue StandardError => e
            warn "  aviso: resync_legs #{ext_id}: #{e.class}: #{e.message}"
          end
        end
        puts "#{ext_id} → #{res}"
        updated += 1
      else
        missing << ext_id
      end
    end
    puts "--- Atualizados #{updated}/#{ID_TO_RESULT.size} bilhete(s)."
    warn "IDs não encontrados (rode nba:import_lac_gsw_apr12_placed_suggestions antes): #{missing.join(', ')}" if missing.any?
  end
end

# Resultados fechados a partir dos bilhetes (Ganhou / Perdida / Anulada).
module PlacedAiSuggestionsResultsApr2026
  module_function

  # external_bet_id => result (PlacedAiSuggestion::RESULTS)
  ID_TO_RESULT = {
    '9690899997' => 'void',   # DEN @ OKC — Criar aposta @7,00 — Anulada (estorno)
    '9690717600' => 'loss',   # Cade Cunningham 8+ AST
    '9690714406' => 'win',    # LaMelo Ball 6+ AST
    '9690916516' => 'loss',   # Dupla (DEN/OKC + HOU/MIN)
    '9690914674' => 'loss',   # Dupla (builder maior HOU/MIN)
    '9690870848' => 'loss',   # CHI @ ORL — parlay (Tre Jones 6+ AST não bateu)
    '9690852171' => 'loss',   # Tripla (ATL/CLE — Mobley 3+ AST não bateu)
    '9690814132' => 'loss',   # ATL @ CLE — parlay (Mobley 3+ AST não bateu)
    '9690727775' => 'win',    # Brandon Miller 17+ PTS
    '9690726171' => 'loss',   # Miles Bridges 15+ PTS
    '9690724623' => 'win',    # Jalen Duren 16+ PTS
    '9690712035' => 'loss',   # Jalen Duren 10+ REB
    '9690710544' => 'loss',   # Moussa Diabaté 8+ REB
    '9690708581' => 'win',    # Duncan Robinson 2+ 3PM
    '9690707045' => 'loss'    # Parlay CHA/DET — Duren 10+ REB não bateu
  }.freeze

  def apply!(user)
    updated = 0
    missing = []
    ID_TO_RESULT.each do |ext_id, res|
      rec = user.placed_ai_suggestions.find_by(external_bet_id: ext_id)
      if rec
        rec.update!(result: res)
        puts "#{ext_id} → #{res}"
        updated += 1
      else
        missing << ext_id
      end
    end
    puts "--- Atualizados #{updated}/#{ID_TO_RESULT.size} bilhete(s)."
    warn "IDs não encontrados (rode os imports antes): #{missing.join(', ')}" if missing.any?
  end
end
