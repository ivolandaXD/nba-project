module Web::ApplicationHelper
  def dash_num(val, suffix = '')
    return '—' if val.nil?

    "#{val}#{suffix}"
  end

  def metrics_bundle_for_player(player, game)
    opp = Ai::GamePlayerAnalysis.opponent_team_for(player, game)
    base = PlayerMetrics::Calculator.cached_payload(player, stat_key: :points, line: nil, opponent_team: opp)
    line = base[:for_ai][:season_avg].present? ? base[:for_ai][:season_avg].round(1) : 20.0
    full = PlayerMetrics::Calculator.cached_payload(player, stat_key: :points, line: line, opponent_team: opp)
    m = full[:for_ai]
    confidence_hint = PlayerMetrics::ConfidenceScorer.call(full[:scorer_inputs])
    {
      default_line: line,
      confidence_hint: confidence_hint,
      season_avg: m[:season_avg],
      last_10: m[:last_10_avg],
      vs_opponent: m[:vs_opponent_avg],
      std_dev: m[:std_dev],
      variance: m[:variance],
      cv: m[:coefficient_of_variation],
      over_15: m[:over_15_rate],
      over_20: m[:over_20_rate],
      over_25: m[:over_25_rate],
      streak: m[:streak_status],
      trend: m[:trend],
      minutes_avg: m[:minutes_avg],
      ppm: m[:points_per_minute],
      usage: m[:usage_rate],
      over_line_rate: m[:over_line_rate],
      home_avg: m[:home_avg],
      away_avg: m[:away_avg]
    }
  end

  def player_scenario_rail_class(score)
    s = score.to_i
    return 'border-l-4 border-slate-300' if s.nil? || s <= 0
    return 'border-l-4 border-emerald-500' if s >= 70
    return 'border-l-4 border-amber-500' if s >= 40
    'border-l-4 border-red-500'
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

    base = 'rounded-xl border-2 p-5 shadow-sm '
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
    when :probability
      return 'bg-emerald-100 text-emerald-900' if v.include?('alta')
      return 'bg-red-100 text-red-900' if v.include?('baixa') || v == 'baix'
      'bg-amber-100 text-amber-900'
    when :risk
      return 'bg-emerald-100 text-emerald-900' if v.include?('baixo') || v == 'baix'
      return 'bg-red-100 text-red-900' if v.include?('alto') || v == 'alt'
      'bg-amber-100 text-amber-900'
    when :value
      return 'bg-emerald-100 text-emerald-900' if v.include?('sim')
      return 'bg-slate-200 text-slate-800' if v.include?('nao') || v.include?('não')
      'bg-amber-100 text-amber-900'
    else
      'bg-slate-100 text-slate-800'
    end
  end
end
