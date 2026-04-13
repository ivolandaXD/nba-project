# frozen_string_literal: true

# Gera o mesmo relatório textual usado para análise manual de props (PSS, split,
# L10 em PTS/3PM/REB/AST) para todos os jogos de um dia no banco.
class PropDaySnapshot
  def self.call(date:, season: Nba::Season.current, out: $stdout)
    new(date: date, season: season, out: out).call
  end

  def initialize(date:, season:, out:)
    @date = date.is_a?(Date) ? date : Date.parse(date.to_s)
    @season = season.to_s.strip
    @out = out
  end

  def call
    games = Game.where(game_date: @date).order(:id)
    w "================================================================================"
    w "PROP SNAPSHOT — #{@date.strftime('%Y-%m-%d')} (#{games.count} jogo(s))"
    w "Temporada: #{@season} · L10 = 10 últimos game logs com PTS no banco"
    w "================================================================================"
    w ''

    if games.empty?
      w "Nenhum Game com game_date=#{@date}. Sincronize o scoreboard (ESPN) para esta data."
      return
    end

    games.each { |g| dump_game(g) }
    w ''
    w "Fim."
  end

  private

  def w(line)
    @out.puts(line)
  end

  def dump_game(game)
    roster = GameRoster.new(game: game, season: @season)
    w "################################################################################"
    w "JOGO: id=#{game.id} · #{game.game_date} · #{game.away_team} @ #{game.home_team} · #{game.status}"
    w "################################################################################"
    w ''

    players = roster.all_players
    if players.empty?
      w '(Sem elenco resolvido — confira abreviações vs players.team / player_season_stats.)'
      w ''
      return
    end

    players.each { |p| dump_player(p, game) }
    w ''
  end

  def dump_player(player, game)
    pss = PlayerSeasonStat.find_by(player_id: player.id, season: @season)
    opp = Ai::GamePlayerAnalysis.opponent_team_for(player, game)
    opp_abbr = NbaStats::OpponentInferrer.canonical_abbr(opp.to_s).presence || opp.to_s.upcase
    split = player.player_opponent_splits.find_by(season: @season, opponent_team: opp_abbr) if opp_abbr.present?
    logs = player.player_game_stats.where.not(points: nil).order(game_date: :desc).limit(10)
    pts = logs.map(&:points)
    th = logs.map(&:three_pt_made)
    rb = logs.map(&:rebounds)
    ast = logs.map(&:assists)

    w '---'
    w player.name
    w player.team.to_s
    w 'vs'
    w opp.to_s
    w 'abbr'
    w opp_abbr.to_s
    w '  PSS:'
    if pss
      fg3 = pss.respond_to?(:fg3m) ? pss.fg3m.to_s : 'n/a'
      w "gp=#{pss.gp} min=#{pss.min} pts=#{pss.pts} reb=#{pss.reb} ast=#{pss.ast} fg3m=#{fg3}"
    else
      w '(sem)'
    end
    w '  Split:'
    if split
      w "gp=#{split.gp} pts=#{split.avg_points} reb=#{split.avg_rebounds} ast=#{split.avg_assists} 3pm=#{split.avg_three_pt_made}"
    else
      w '(sem)'
    end
    w '  L10 PTS:'
    w pts.inspect
    l5 = pts.first(5).compact
    l5avg = l5.empty? ? nil : (l5.sum.to_f / l5.size).round(2)
    w 'L5 avg pts:'
    w(l5avg.nil? ? '—' : l5avg.to_s)
    w '  L10 3PM:'
    w th.compact.inspect
    w '  L10 REB:'
    w rb.compact.inspect
    w 'AST:'
    w ast.compact.inspect
    w ''
  end
end
