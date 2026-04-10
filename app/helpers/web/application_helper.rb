module Web::ApplicationHelper
  def ai_hub_sort_link(label, column, current_sort:, current_dir:, q:, game_id:)
    next_dir = current_sort.to_s == column.to_s && current_dir.to_s == 'asc' ? 'desc' : 'asc'
    arrow =
      if current_sort.to_s == column.to_s
        current_dir.to_s == 'asc' ? ' ▲' : ' ▼'
      else
        ''
      end
    link_to "#{label}#{arrow}",
            ai_hub_path(q: q.presence, game_id: game_id.presence, sort: column, dir: next_dir),
            class: 'text-slate-700 hover:text-orange-700 font-semibold'
  end

  def season_stats_sort_link(label, column, current_sort:, current_dir:, q:, per:, page:)
    next_dir = current_sort.to_s == column.to_s && current_dir.to_s == 'asc' ? 'desc' : 'asc'
    arrow =
      if current_sort.to_s == column.to_s
        current_dir.to_s == 'asc' ? ' ▲' : ' ▼'
      else
        ''
      end
    link_to "#{label}#{arrow}",
            season_stats_path(
              q: q.presence,
              per: per,
              page: page,
              sort: column,
              dir: next_dir
            ),
            class: 'text-slate-700 hover:text-orange-700 font-semibold'
  end

  def pct_cell(decimal)
    return '—' if decimal.nil?

    # stats.nba devolve0.452 para 45.2%
    v = decimal.to_f
    v *= 100 if v <= 1 && v >= 0
    number_to_percentage(v, precision: 1)
  end

  def dash_num(val, suffix = '')
    return '—' if val.nil?

    "#{val}#{suffix}"
  end

  # Elenco na página do jogo: box deste game_id, senão média em player_season_stats.
  def roster_stat_cell(pgs, game_attr, pss, season_attr, precision: 1)
    gv = pgs&.public_send(game_attr) if pgs&.respond_to?(game_attr)
    sv = pss&.public_send(season_attr) if pss&.respond_to?(season_attr)
    gv_ok = !(gv.nil? || (gv.is_a?(String) && gv.strip.empty?))
    sv_ok = !(sv.nil? || (sv.is_a?(String) && sv.strip.empty?))

    txt = lambda do |val|
      val.is_a?(Integer) ? val.to_s : number_with_precision(val, precision: precision)
    end

    if gv_ok
      content_tag(:span, txt.call(gv), class: 'text-slate-900 font-medium tabular-nums', title: 'Box score · este jogo')
    elsif sv_ok
      content_tag(:span, txt.call(sv), class: 'text-slate-600 tabular-nums', title: 'Média na temporada')
    else
      '—'
    end
  end

  def roster_fg_made_att_cell(pgs, pss)
    g_fgm = pgs&.respond_to?(:fgm) ? pgs.fgm : nil
    g_fga = pgs&.respond_to?(:fga) ? pgs.fga : nil
    s_fgm = pss&.respond_to?(:fgm) ? pss.fgm : nil
    s_fga = pss&.respond_to?(:fga) ? pss.fga : nil

    g_ok = !(g_fgm.nil? && g_fga.nil?)
    s_ok = !(s_fgm.nil? && s_fga.nil?)

    if pgs && g_ok
      content_tag(:span, "#{g_fgm}/#{g_fga}", class: 'text-slate-900 font-medium tabular-nums whitespace-nowrap', title: 'Box score · este jogo')
    elsif pss && s_ok
      a = s_fgm.nil? ? '—' : number_with_precision(s_fgm, precision: 1)
      b = s_fga.nil? ? '—' : number_with_precision(s_fga, precision: 1)
      content_tag(:span, "#{a}/#{b}", class: 'text-slate-600 tabular-nums whitespace-nowrap', title: 'Média na temporada')
    else
      '—'
    end
  end

  # Player props pontos no contexto de um jogo (inclui vs adversário).
  def metrics_bundle_for_player(player, game)
    opp = Ai::GamePlayerAnalysis.opponent_team_for(player, game)
    base = PlayerMetrics::Calculator.cached_payload(player, stat_key: :points, line: nil, opponent_team: opp)
    m0 = base[:for_ai]
    season = m0[:season_avg_points].presence || m0[:season_avg]
    line = season.present? ? season.to_f.round(1) : 20.0
    full = PlayerMetrics::Calculator.cached_payload(player, stat_key: :points, line: line, opponent_team: opp)
    m = full[:for_ai]
    confidence_hint = PlayerMetrics::ConfidenceScorer.call(full[:scorer_inputs])
    {
      default_line: line,
      confidence_hint: confidence_hint,
      season_avg: m[:season_avg_points],
      last_5: m[:last_5_avg_points],
      last_10: m[:last_10_avg_points],
      vs_opponent: m[:vs_opponent_avg_points],
      std_dev: m[:std_dev_points],
      variance: m[:variance_points],
      cv: m[:coefficient_of_variation],
      over_15: m[:over_15_rate],
      over_20: m[:over_20_rate],
      over_25: m[:over_25_rate],
      streak: m[:streak_status],
      trend: m[:trend],
      trend_last_10: m[:trend_last_10_vs_season],
      minutes_avg: m[:minutes_avg],
      fga_avg: m[:fga_avg],
      fta_avg: m[:fta_avg],
      ppm: m[:points_per_minute],
      usage: m[:usage_fga_fta_avg],
      over_line_rate: m[:over_line_rate],
      home_avg: m[:home_avg_points],
      away_avg: m[:away_avg_points]
    }
  end

  # Snapshot de props de pontos sem jogo (sem split vs time).
  def player_points_props_snapshot(player)
    base = PlayerMetrics::Calculator.cached_payload(player, stat_key: :points, line: nil, opponent_team: nil)
    m0 = base[:for_ai]
    season = m0[:season_avg_points].presence || m0[:season_avg]
    line = season.present? ? season.to_f.round(1) : 20.0
    full = PlayerMetrics::Calculator.cached_payload(player, stat_key: :points, line: line, opponent_team: nil)
    m = full[:for_ai]
    {
      default_line: line,
      confidence_hint: PlayerMetrics::ConfidenceScorer.call(full[:scorer_inputs]),
      m: m
    }
  end

  STAT_PROFILE_SECTIONS = [
    { key: :points, title: 'Pontos', subtitle: 'PTS · scoring', rich: true },
    { key: :rebounds, title: 'Rebotes', subtitle: 'REB · garrafão / vidro' },
    { key: :assists, title: 'Assistências', subtitle: 'AST · jogo de passe' },
    { key: :steals, title: 'Roubos de bola', subtitle: 'STL · defesa ativa' },
    { key: :blocks, title: 'Tocos', subtitle: 'BLK · proteção do aro' },
    { key: :threes, title: 'Triplos marcados', subtitle: '3PM · perimeter' },
    { key: :turnovers, title: 'Perdas de bola', subtitle: 'TOV · cuidado com o balão' }
  ].freeze

  def player_stat_profile_sections(player)
    STAT_PROFILE_SECTIONS.map { |row| row.merge(snapshot: player_stat_profile_snapshot(player, row[:key])) }
  end

  def player_stat_profile_snapshot(player, stat_key)
    stat_key = stat_key.to_sym
    base = PlayerMetrics::Calculator.cached_payload(player, stat_key: stat_key, line: nil, opponent_team: nil)
    m0 = base[:for_ai]
    season =
      if stat_key == :points
        m0[:season_avg_points].presence || m0[:season_avg]
      else
        m0[:season_avg]
      end
    line =
      if season.present?
        v = season.to_f
        v >= 8 ? v.round(1) : v.round(2)
      elsif stat_key == :points
        20.0
      else
        1.0
      end
    full = PlayerMetrics::Calculator.cached_payload(player, stat_key: stat_key, line: line, opponent_team: nil)
    m = full[:for_ai]
    {
      default_line: line,
      confidence: PlayerMetrics::ConfidenceScorer.call(full[:scorer_inputs]),
      m: m,
      stat_key: stat_key
    }
  end

  def stat_profile_season_avg(m, stat_key)
    stat_key.to_sym == :points ? m[:season_avg_points] : m[:season_avg]
  end

  def stat_profile_last_5(m, stat_key)
    stat_key.to_sym == :points ? m[:last_5_avg_points] : m[:last_5_avg]
  end

  def stat_profile_last_10(m, stat_key)
    stat_key.to_sym == :points ? m[:last_10_avg_points] : m[:last_10_avg]
  end

  def stat_profile_std_dev(m, stat_key)
    stat_key.to_sym == :points ? m[:std_dev_points] : m[:std_dev]
  end

  def stat_profile_home(m, stat_key)
    stat_key.to_sym == :points ? m[:home_avg_points] : m[:home_avg]
  end

  def stat_profile_away(m, stat_key)
    stat_key.to_sym == :points ? m[:away_avg_points] : m[:away_avg]
  end

  # Totais e % “verdadeiros” (soma FGM/FGA etc.) a partir dos game logs.
  def player_shooting_rollups(player)
    rel = player.player_game_stats
    return nil unless rel.exists?

    gp = rel.count
    fgm = rel.sum(:fgm).to_i
    fga = rel.sum(:fga).to_i
    thm = rel.sum(:three_pt_made).to_i
    tha = rel.sum(:three_pt_attempted).to_i
    ftm = rel.sum(:ftm).to_i
    fta = rel.sum(:fta).to_i

    pct = ->(made, att) { att.positive? ? (100.0 * made / att).round(1) : nil }

    {
      gp: gp,
      fgm_pg: gp.positive? ? (fgm.to_f / gp).round(2) : nil,
      fga_pg: gp.positive? ? (fga.to_f / gp).round(2) : nil,
      fg_pct: pct.call(fgm, fga),
      thm_pg: gp.positive? ? (thm.to_f / gp).round(2) : nil,
      tha_pg: gp.positive? ? (tha.to_f / gp).round(2) : nil,
      th_pct: pct.call(thm, tha),
      ftm_pg: gp.positive? ? (ftm.to_f / gp).round(2) : nil,
      fta_pg: gp.positive? ? (fta.to_f / gp).round(2) : nil,
      ft_pct: pct.call(ftm, fta)
    }
  end

  def player_scenario_rail_class(score)
    s = score.to_i
    return 'border-l-2 border-slate-300' if s.nil? || s <= 0
    return 'border-l-2 border-emerald-500' if s >= 70
    return 'border-l-2 border-amber-500' if s >= 40
    'border-l-2 border-red-500'
  end

  def streak_badge_class(streak)
    case streak.to_s
    when 'hot'
      'bg-emerald-100 text-emerald-900 border border-emerald-300'
    when 'cold'
      'bg-red-100 text-red-900 border border-red-300'
    else
      'bg-slate-100 text-slate-700 border border-slate-200'
    end
  end

  def ai_prediction_shell_class(pred)
    score = pred.confidence_score.to_i
    meta = pred.analysis_meta || {}
    risk = (meta['risk_level'] || meta[:risk_level]).to_s.downcase

    base = 'rounded-xl border-2 p-4 shadow-sm '
    score_tone =
      if score >= 70
        'border-emerald-300 bg-emerald-50/90'
      elsif score >= 40
        'border-amber-300 bg-amber-50/90'
      else
        'border-red-300 bg-red-50/90'
      end

    return base + score_tone if risk.blank?

    risk_tone =
      if risk.include?('baixo') || risk == 'baix'
        ' ring-2 ring-emerald-200'
      elsif risk.include?('alto') || risk == 'alt'
        ' ring-2 ring-red-200'
      else
        ' ring-2 ring-amber-200'
      end

    base + score_tone + risk_tone
  end

  def ai_meta_pill_classes(kind, value)
    v = value.to_s.downcase
    case kind
    when :probability, :line_hit
      return 'bg-emerald-100 text-emerald-900' if v.include?('alta')
      return 'bg-red-100 text-red-900' if v.include?('baixa') || v == 'baix'
      'bg-amber-100 text-amber-900'
    when :trend
      return 'bg-emerald-100 text-emerald-900' if v.include?('alta')
      return 'bg-red-100 text-red-900' if v.include?('queda')
      'bg-amber-100 text-amber-900'
    when :risk
      return 'bg-emerald-100 text-emerald-900' if v.include?('baixo') || v == 'baix'
      return 'bg-red-100 text-red-900' if v.include?('alto') || v == 'alt'
      'bg-amber-100 text-amber-900'
    when :value
      return 'bg-emerald-100 text-emerald-900' if v.include?('sim')
      return 'bg-slate-200 text-slate-800' if v.include?('nao') || v.include?('não')
      'bg-amber-100 text-amber-900'
    when :recommendation
      return 'bg-emerald-100 text-emerald-900' if v.include?('over')
      return 'bg-red-100 text-red-900' if v.include?('under')
      return 'bg-slate-200 text-slate-800' if v.include?('pass')
      'bg-amber-100 text-amber-900'
    else
      'bg-slate-100 text-slate-800'
    end
  end
end
