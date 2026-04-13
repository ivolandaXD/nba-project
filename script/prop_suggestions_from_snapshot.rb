#!/usr/bin/env ruby
# frozen_string_literal: true

# Lê prop_analysis_day_*.txt (snapshot do dia) e gera:
#   1) prop_suggestions_*.txt — lista com tags [PTS]/[REB]/...
#   2) prop_betting_day_*.txt — formato folha de apostas (estilo Charlotte): "N) Jogador — linha -- ODD - ___" + narrativa PSS/L5/L10
# Uso: ruby script/prop_suggestions_from_snapshot.rb [SNAPSHOT] [OUT_SUGGESTIONS] [OUT_BETTING]

path = ARGV[0] || File.expand_path('../prop_analysis_day_2026-04-10.txt', __dir__)
out_path = ARGV[1] || File.expand_path('../prop_suggestions_day_2026-04-10.txt', __dir__)
# Terceiro argumento: ficheiro estilo Charlotte (ODD ___). Se omitido, gera prop_betting_day_YYYY-MM-DD.txt ao lado do snapshot.
betting_path =
  if ARGV[2] && !ARGV[2].strip.empty?
    File.expand_path(ARGV[2])
  else
    d = File.basename(path).match(/(\d{4}-\d{2}-\d{2})/)
    suf = d ? d[1] : 'slate'
    File.expand_path("../prop_betting_day_#{suf}.txt", File.dirname(path))
  end

def parse_int_array(str)
  return [] if str.nil? || !str.include?('[')

  str.scan(/-?\d+/).map(&:to_i)
end

def parse_pss(line)
  return nil if line.nil? || line.include?('(sem)')

  m = line.match(/gp=(\d+)\s+min=([\d.]+)\s+pts=([\d.]+)\s+reb=([\d.]+)\s+ast=([\d.]+)\s+fg3m=([\d.n\/a]+)/i)
  return nil unless m

  {
    gp: m[1].to_i,
    min: m[2].to_f,
    pts: m[3].to_f,
    reb: m[4].to_f,
    ast: m[5].to_f,
    fg3m: (m[6] =~ /\d/ ? m[6].to_f : 0.0)
  }
end

def hit_rate(vals, threshold)
  v = vals.compact
  return 0.0 if v.empty?

  v.count { |x| x >= threshold } / v.size.to_f
end

def score_prop(_kind, threshold, rate)
  # Mesma escala para todos os mercados (PTS não domina o ranking).
  rate * Math.log([threshold.to_f, 1.0].max + 2.0)
end

# Até 10 ideias por jogo com mix fixo; o que faltar num mercado completa pelos melhores scores.
def pick_balanced(pool, max_total: 10, max_per_player: 2)
  by_kind = { 'pts' => [], 'reb' => [], 'ast' => [], 'th' => [] }
  pool.each do |c|
    k = c[:kind]
    by_kind[k] << c if by_kind.key?(k)
  end
  by_kind.each_value { |arr| arr.sort_by! { |c| -c[:score] } }

  quota = { 'th' => 2, 'ast' => 2, 'reb' => 3, 'pts' => 3 }
  picked = []
  used_tag = {}
  player_n = Hash.new(0)

  take_from = lambda do |kind|
    by_kind[kind].each do |c|
      next if used_tag[c[:tag]]
      name = c[:player_name]
      next if player_n[name] >= max_per_player

      used_tag[c[:tag]] = true
      picked << c
      player_n[name] += 1
      return true
    end
    false
  end

  quota.each do |kind, need|
    need.times { break unless take_from.call(kind) }
  end

  pool.sort_by { |c| -c[:score] }.each do |c|
    break if picked.size >= max_total
    next if used_tag[c[:tag]]
    name = c[:player_name]
    next if player_n[name] >= max_per_player

    used_tag[c[:tag]] = true
    picked << c
    player_n[name] += 1
  end

  picked.first(max_total)
end

def candidates_for_player(name, team, pss, pts10, reb10, ast10, th10)
  return [] if pss.nil? || pss[:min] < 18.0 || pss[:gp] < 12

  out = []
  base = pss[:pts]
  min_pts_line =
    if base >= 16.0
      [10, (base * 0.55).floor].max
    elsif base >= 10.0
      [8, (base * 0.5).floor].max
    else
      [6, (base * 0.45).floor].max
    end

  # Pontos: patamares decrescentes; corta linhas triviais
  [base.floor, (base - 2).floor, (base - 4).floor, (base - 6).floor, 28, 25, 22, 20, 18, 15, 12, 10].uniq.sort.reverse.each do |x|
    next if x < min_pts_line

    r = hit_rate(pts10, x)
    next if r < 0.55

    sc = score_prop('pts', x, r)
    out << {
      player_name: name,
      team: team,
      kind: 'pts',
      threshold: x,
      tag: "#{name} (#{team}) — #{x}+ PTS",
      rate: r,
      score: sc,
      note: "PSS #{base.round(1)} · L10 ≥#{x}: #{(r * 100).round}%"
    }
    break if out.count { |c| c[:tag].start_with?(name) && c[:tag].include?('PTS') } >= 2
  end

  rb = pss[:reb]
  min_reb = [4, (rb * 0.55).floor].max
  [rb.floor, (rb - 1).floor, (rb - 2).floor, 12, 10, 8, 6].uniq.sort.reverse.each do |x|
    next if x < min_reb

    r = hit_rate(reb10, x)
    next if r < 0.55

    out << {
      player_name: name,
      team: team,
      kind: 'reb',
      threshold: x,
      tag: "#{name} (#{team}) — #{x}+ REB",
      rate: r,
      score: score_prop('reb', x, r),
      note: "PSS #{rb.round(1)} reb · L10 ≥#{x}: #{(r * 100).round}%"
    }
    break if out.count { |c| c[:tag].start_with?(name) && c[:tag].include?('REB') } >= 1
  end

  ast = pss[:ast]
  if ast >= 3.0
    min_ast = [3, (ast * 0.5).floor].max
    [ast.floor, (ast - 1).floor, (ast - 2).floor, 10, 8, 6].uniq.sort.reverse.each do |x|
      next if x < min_ast

      r = hit_rate(ast10, x)
      next if r < 0.5

      out << {
        player_name: name,
        team: team,
        kind: 'ast',
        threshold: x,
        tag: "#{name} (#{team}) — #{x}+ AST",
        rate: r,
        score: score_prop('ast', x, r),
        note: "PSS #{ast.round(1)} ast · L10 ≥#{x}: #{(r * 100).round}%"
      }
      break if out.count { |c| c[:tag].start_with?(name) && c[:tag].include?('AST') } >= 1
    end
  end

  th = pss[:fg3m]
  # Shooting (triplos): sem 1+; volume mínimo um pouco mais baixo para entrar snipers.
  if th >= 1.15 && th10.compact.sum.positive?
    [4, 3, 2].each do |x|
      next if x == 4 && th < 2.0

      r = hit_rate(th10, x)
      next if r < 0.5

      out << {
        player_name: name,
        team: team,
        kind: 'th',
        threshold: x,
        tag: "#{name} (#{team}) — #{x}+ 3PM",
        rate: r,
        score: score_prop('th', x, r),
        note: "PSS #{th.round(1)} 3PM · L10 ≥#{x}: #{(r * 100).round}%"
      }
      break
    end
  end

  out
end

def hash_separator_line?(s)
  t = s.to_s.strip
  t.length >= 20 && t.gsub('#', '').empty?
end

def parse_games(lines)
  games = []
  i = 0
  while i < lines.size
    if lines[i].start_with?('JOGO:')
      header = lines[i]
      i += 1
      i += 1 while i < lines.size && (lines[i].strip.empty? || hash_separator_line?(lines[i]))

      players = []
      while i < lines.size && !lines[i].start_with?('JOGO:') && !hash_separator_line?(lines[i])
        if lines[i] == '---'
          block = []
          i += 1
          while i < lines.size && lines[i] != '---' && !lines[i].start_with?('JOGO:') && !hash_separator_line?(lines[i])
            block << lines[i]
            i += 1
          end
          players << block
        else
          i += 1
        end
      end

      i += 1 while i < lines.size && (hash_separator_line?(lines[i]) || lines[i].strip.empty?)
      games << { header: header, raw_players: players }
    else
      i += 1
    end
  end
  games
end

def parse_player_block(block)
  return nil if block.size < 12

  name = block[0].to_s.strip
  team = block[1].to_s.strip
  idx_pss = block.index { |l| l.to_s.strip == 'PSS:' }
  return nil unless idx_pss

  pss_line = block[idx_pss + 1].to_s.strip
  pss = parse_pss(pss_line)

  idx_l10pts = block.index { |l| l.to_s.include?('L10 PTS:') }
  pts10 = idx_l10pts ? parse_int_array(block[idx_l10pts + 1]) : []

  idx_th = block.index { |l| l.to_s.include?('L10 3PM:') }
  th10 = idx_th ? parse_int_array(block[idx_th + 1]) : []

  idx_rb = block.index { |l| l.to_s.include?('L10 REB:') }
  reb10 = idx_rb ? parse_int_array(block[idx_rb + 1]) : []

  idx_ast = block.index { |l| l.to_s.strip == 'AST:' }
  ast10 = idx_ast ? parse_int_array(block[idx_ast + 1]) : []

  { name: name, team: team, pss: pss, pts10: pts10, reb10: reb10, ast10: ast10, th10: th10 }
rescue StandardError
  nil
end

def avg_first_n(arr, n)
  v = arr.first(n).compact
  v.empty? ? 0.0 : v.sum.to_f / v.size
end

def hits_l10(arr, th)
  vals = arr.compact
  n = vals.count { |v| v >= th }
  [n, vals.size]
end

def prop_title_pt_betting(c)
  desc = case c[:kind]
         when 'pts' then "#{c[:threshold]}+ pontos"
         when 'reb' then "#{c[:threshold]}+ rebotes"
         when 'ast' then "#{c[:threshold]}+ assistências"
         when 'th' then "#{c[:threshold]}+ bolas de três"
         else "#{c[:threshold]}+"
         end
  "#{c[:player_name]} — #{desc}"
end

def narrative_betting_line(c, pl)
  th = c[:threshold]
  return c[:note] unless pl && pl[:pss]

  case c[:kind]
  when 'pts'
    l5 = avg_first_n(pl[:pts10], 5)
    n, tot = hits_l10(pl[:pts10], th)
    r = tot.positive? ? (n.to_f / tot * 100).round : 0
    "PSS #{pl[:pss][:pts].round(1)} pts ; L5 ~#{l5.round(1)} ; L10 ≥#{th}: #{n}/#{tot} (#{r}%)."
  when 'reb'
    l5 = avg_first_n(pl[:reb10], 5)
    n, tot = hits_l10(pl[:reb10], th)
    r = tot.positive? ? (n.to_f / tot * 100).round : 0
    "PSS #{pl[:pss][:reb].round(1)} reb ; L5 ~#{l5.round(1)} ; L10 ≥#{th}: #{n}/#{tot} (#{r}%)."
  when 'ast'
    l5 = avg_first_n(pl[:ast10], 5)
    n, tot = hits_l10(pl[:ast10], th)
    r = tot.positive? ? (n.to_f / tot * 100).round : 0
    "PSS #{pl[:pss][:ast].round(1)} ast ; L5 ~#{l5.round(1)} ; L10 ≥#{th}: #{n}/#{tot} (#{r}%)."
  when 'th'
    n, tot = hits_l10(pl[:th10], th)
    r = tot.positive? ? (n.to_f / tot * 100).round : 0
    "PSS #{pl[:pss][:fg3m].round(1)} 3PM ; L10 ≥#{th}: #{n}/#{tot} (#{r}%)."
  else
    c[:note]
  end
end

def slate_date_label(path, games)
  if File.basename(path) =~ /(\d{4})-(\d{2})-(\d{2})/
    return "#{::Regexp.last_match(3)}/#{::Regexp.last_match(2)}/#{::Regexp.last_match(1)}"
  end

  h = games[0]&.dig(:header).to_s
  if h =~ /(\d{4})-(\d{2})-(\d{2})/
    return "#{::Regexp.last_match(3)}/#{::Regexp.last_match(2)}/#{::Regexp.last_match(1)}"
  end

  '(data no nome do ficheiro / cabeçalho JOGO)'
end

lines = File.read(path, encoding: 'UTF-8').lines.map(&:chomp)
games = parse_games(lines)

games_data = games.map do |g|
  parsed = g[:raw_players].map { |b| parse_player_block(b) }.compact
  pool = []
  parsed.each do |pl|
    next unless pl[:pss]

    pool.concat(candidates_for_player(pl[:name], pl[:team], pl[:pss], pl[:pts10], pl[:reb10], pl[:ast10], pl[:th10]))
  end
  pool.uniq! { |c| c[:tag] }
  top = pick_balanced(pool, max_total: 10, max_per_player: 2)
  by_name = {}
  parsed.each { |pl| by_name[pl[:name]] = pl }
  { header: g[:header], parsed: parsed, top: top, by_name: by_name }
end

File.open(out_path, 'w:UTF-8') do |io|
  io.puts '=' * 80
  io.puts 'SUGESTÕES DE PROPS (HEURÍSTICA) — gerado a partir do snapshot do dia'
  io.puts "Origem: #{File.basename(path)}"
  io.puts 'Mix por jogo (alvo): 3 PTS + 3 REB + 2 AST + 2 triplos; completa até 10 pelos melhores scores. Máx. 2 props por jogador.'
  io.puts 'Filtros: PSS min≥18, gp≥12; L10 ≥55% (triplos/AST ≥50%); triplos só 2+ ou mais; não é EV nem previsão.'
  io.puts 'Isto NÃO é previsão nem EV; cruza com odds antes de apostar.'
  io.puts '=' * 80
  io.puts

  games_data.each do |gd|
    io.puts '#' * 80
    io.puts gd[:header]
    io.puts '#' * 80

    if gd[:parsed].empty?
      io.puts '(Sem jogadores parseados.)'
      io.puts
      next
    end

    if gd[:top].empty?
      io.puts 'Nenhuma sugestão passou nos filtros (dados fracos ou L10 curto).'
    else
      lab = { 'pts' => 'PTS', 'reb' => 'REB', 'ast' => 'AST', 'th' => '3PM' }
      gd[:top].each_with_index do |c, idx|
        io.puts "#{idx + 1}. [#{lab[c[:kind]]}] #{c[:tag]}"
        io.puts "   #{c[:note]}"
      end
    end
    io.puts
  end

  io.puts 'Fim.'
end

date_lbl = slate_date_label(path, games)
File.open(betting_path, 'w:UTF-8') do |io|
  io.puts '=' * 80
  io.puts "SLATE DE PROPS (formato folha de apostas) — #{date_lbl}"
  io.puts "#{games_data.size} jogos · mesma heurística que prop_suggestions (mix PTS/REB/AST/3PM; até 10 props por jogo; máx. 2 por jogador)."
  io.puts "Fonte snapshot: #{File.basename(path)}"
  io.puts '=' * 80
  io.puts
  io.puts 'O QUE É L5 / L10?'
  io.puts '-' * 80
  io.puts '• L5 = média dos 5 jogos mais recentes no teu dump (player_game_stats).'
  io.puts '• L10 = taxa / contagens nos 10 jogos mais recentes (≥ linha da prop).'
  io.puts '• PSS = médias da temporada (player_season_stats). Cruza tudo com odds reais antes de apostar.'
  io.puts
  io.puts '=' * 80
  io.puts 'PROP POR JOGO — preencher ODD (substituir ___)'
  io.puts '=' * 80
  io.puts

  games_data.each do |gd|
    io.puts '#' * 80
    io.puts gd[:header]
    io.puts '#' * 80
    io.puts

    if gd[:parsed].empty?
      io.puts '(Sem jogadores parseados.)'
      io.puts
      next
    end

    if gd[:top].empty?
      io.puts 'Nenhuma prop passou nos filtros para este jogo.'
      io.puts
      next
    end

    gd[:top].each_with_index do |c, idx|
      pl = gd[:by_name][c[:player_name]]
      io.puts "#{idx + 1}) #{prop_title_pt_betting(c)} -- ODD - ___"
      io.puts narrative_betting_line(c, pl)
      io.puts
    end
  end

  io.puts 'Fim.'
end

puts "Escrito: #{out_path} (#{File.size(out_path)} bytes)"
puts "Folha de apostas: #{betting_path} (#{File.size(betting_path)} bytes)"
