module Ai
  class GamePlayerAnalysis
    def self.opponent_team_for(player, game)
      return game.away_team if player.team.to_s == game.home_team.to_s
      return game.home_team if player.team.to_s == game.away_team.to_s

      nil
    end

    def self.call(game:, player:, line: nil, bet_type: 'points', odds: nil, confidence_score: nil, user_note: nil, params: nil,
                  prop_focus: [], portfolio_mode: false)
      opponent = opponent_team_for(player, game)
      stat_key = bet_type.to_sym
      line_val = line.present? ? line.to_f : nil

      focus = normalize_prop_focus(prop_focus, bet_type)
      use_portfolio = portfolio_mode || focus.size > 1

      if use_portfolio
        payload_primary = PlayerMetrics::Calculator.cached_payload(
          player,
          stat_key: stat_key,
          line: line_val,
          opponent_team: opponent
        )
        computed = PlayerMetrics::ConfidenceScorer.call(payload_primary[:scorer_inputs])
        input = build_portfolio_input(
          game: game,
          player: player,
          opponent: opponent,
          prop_focus: focus,
          primary_stat: stat_key,
          line_val: line_val,
          odds: odds,
          computed: computed,
          user_note: user_note,
          params: params
        )
        merge_opponent_context!(input, game: game, player: player, opponent: opponent)
        return run_openai_and_persist(game: game, player: player, input: input, computed: computed, confidence_score: confidence_score)
      end

      payload = PlayerMetrics::Calculator.cached_payload(
        player,
        stat_key: stat_key,
        line: line_val,
        opponent_team: opponent
      )

      computed = PlayerMetrics::ConfidenceScorer.call(payload[:scorer_inputs])

      base = payload[:for_ai].dup
      input =
        if stat_key == :points
          build_points_props_input(
            base,
            game: game,
            line_val: line_val,
            odds: odds,
            computed: computed,
            user_note: user_note,
            player: player,
            opponent: opponent,
            params: params
          )
        else
          base.merge(
            line: line_val,
            odds: odds.presence,
            confidence_score_model: computed,
            user_note: user_note.to_s.strip.presence
          ).compact
        end

      merge_opponent_context!(input, game: game, player: player, opponent: opponent) if stat_key == :points

      run_openai_and_persist(game: game, player: player, input: input, computed: computed, confidence_score: confidence_score)
    rescue StandardError => e
      Rails.logger.error("[GamePlayerAnalysis] #{e.class}: #{e.message}")
      { ok: false, error: e.message, prediction: nil }
    end

    def self.run_openai_and_persist(game:, player:, input:, computed:, confidence_score: nil)
      ai = OpenAiAnalyzer.call(input)
      return { ok: false, error: ai.error, prediction: nil } unless ai.success?

      meta = (ai.structured.presence || {}).stringify_keys
      meta = OpenAiAnalyzer.normalize_structured(meta) if meta.present?

      decision = input[:decision_score].presence || input['decision_score'].presence || confidence_score.presence || computed
      numeric_meta = build_numeric_meta(input, computed: computed, decision_score: decision)

      prediction = AiPrediction.create!(
        game: game,
        player: player,
        input_data: input.deep_stringify_keys,
        output_text: ai.prediction,
        confidence_score: decision,
        analysis_meta: meta.merge(numeric_meta.compact)
      )
      { ok: true, error: nil, prediction: prediction }
    end

    def self.normalize_prop_focus(raw, bet_type)
      arr = Array(raw).map(&:to_s).reject(&:blank?)
      allowed = PlayerMetrics::Calculator::STAT_COLUMNS.keys.map(&:to_s)
      return [bet_type.to_s] if arr.empty?
      return allowed.dup if arr.include?('all')

      (arr & allowed).presence || [bet_type.to_s]
    end

    def self.compact_portfolio_block(stat_sym, for_ai)
      h = for_ai.deep_stringify_keys
      if stat_sym == :points
        h.slice(
          'season_avg_points', 'last_5_avg_points', 'last_10_avg_points', 'vs_opponent_avg_points',
          'std_dev_points', 'coefficient_of_variation', 'minutes_avg', 'over_15_rate', 'over_20_rate', 'over_25_rate',
          'over_line_rate', 'streak_status', 'trend', 'home_avg_points', 'away_avg_points'
        )
      else
        h.slice(
          'stat', 'season_avg', 'last_5_avg', 'last_10_avg', 'vs_opponent_avg', 'std_dev',
          'coefficient_of_variation', 'minutes_avg', 'streak_status', 'trend', 'home_avg', 'away_avg', 'over_line_rate'
        )
      end
    end

    def self.build_portfolio_input(game:, player:, opponent:, prop_focus:, primary_stat:, line_val:, odds:, computed:, user_note:, params:)
      manual = PlayerProps::ManualContext.from_params(params || {}, player: player, game: game)
      markets_data = {}
      prop_focus.each do |k|
        sym = k.to_sym
        next unless PlayerMetrics::Calculator::STAT_COLUMNS.key?(sym)

        pl = PlayerMetrics::Calculator.cached_payload(player, stat_key: sym, line: nil, opponent_team: opponent)
        markets_data[sym.to_s] = compact_portfolio_block(sym, pl[:for_ai]).merge('label' => sym.to_s)
      end

      {
        analysis_mode: 'props_portfolio',
        player: { id: player.id, name: player.name, team: player.team },
        primary_market: primary_stat.to_s,
        primary_line: line_val,
        odds: odds.presence,
        confidence_score_model: computed,
        markets_included: prop_focus,
        markets_data: markets_data,
        game_context: {
          'home_team' => game.home_team,
          'away_team' => game.away_team,
          'game_date' => game.game_date&.to_s,
          'opponent_team_abbr' => opponent
        }.compact,
        manual_game_context: manual.deep_stringify_keys,
        user_note: user_note.to_s.strip.presence,
        instruction: 'Sugira várias ideias de props (ex.: 20+ PTS, 2+ 3PM, 8+ REB) com faixas coerentes com as médias; não assuma uma aposta única.'
      }.compact
    end

    def self.build_numeric_meta(input, computed:, decision_score:)
      h = input.deep_stringify_keys
      {
        'probability_over_percent' => h['probability_over_percent'],
        'implied_probability_percent' => h['implied_probability_percent'],
        'adjusted_probability_percent' => h['adjusted_probability_percent'],
        'ev' => h['ev'],
        'ev_base' => h['ev_base'],
        'context_modifier_total_percent_points' => h['context_modifier_total_percent_points'],
        'context_modifiers_applied' => h['context_modifiers_applied'],
        'confidence_score_model' => computed,
        'decision_score' => decision_score,
        'manual_game_context' => h['manual_game_context']
      }
    end

    def self.build_points_props_input(base, game:, line_val:, odds:, computed:, user_note:, player:, opponent:, params:)
      h = base.stringify_keys
      core = {
        player: h['player'] || { 'id' => player.id, 'name' => player.name, 'team' => player.team },
        stat: 'points',
        line: line_val,
        odds: odds.presence,
        season_avg_points: h['season_avg_points'],
        last_5_avg_points: h['last_5_avg_points'],
        last_10_avg_points: h['last_10_avg_points'],
        vs_opponent_avg_points: h['vs_opponent_avg_points'],
        std_dev_points: h['std_dev_points'],
        variance_points: h['variance_points'],
        coefficient_of_variation: h['coefficient_of_variation'],
        over_15_rate: h['over_15_rate'],
        over_20_rate: h['over_20_rate'],
        over_25_rate: h['over_25_rate'],
        over_line_rate: h['over_line_rate'],
        trend: h['trend'],
        trend_last_10_vs_season: h['trend_last_10_vs_season'],
        minutes_avg: h['minutes_avg'],
        fga_avg: h['fga_avg'],
        fta_avg: h['fta_avg'],
        usage_fga_fta_avg: h['usage_fga_fta_avg'],
        home_avg_points: h['home_avg_points'],
        away_avg_points: h['away_avg_points'],
        streak_status: h['streak_status'],
        points_per_minute: h['points_per_minute'],
        confidence_score_model: computed,
        user_note: user_note.to_s.strip.presence,
        game_context: {
          'home_team' => game.home_team,
          'away_team' => game.away_team,
          'game_date' => game.game_date&.to_s,
          'opponent_team_abbr' => opponent
        }.compact
      }.compact

      manual = PlayerProps::ManualContext.from_params(params || {}, player: player, game: game)
      manual_json = manual.deep_stringify_keys

      prob_over = PlayerProps::ProbabilityEstimator.over_probability(h, line: line_val)
      implied = PlayerProps::AmericanOdds.implied_probability(odds)
      spread_val = manual[:spread]
      adj = PlayerProps::ContextAdjustor.call(
        probability_over: prob_over,
        manual_context: manual,
        spread: spread_val
      )
      adj_p = adj[:adjusted_probability]
      ev = PlayerProps::AmericanOdds.ev_over(p: adj_p, american_odds: odds)
      ev_base = PlayerProps::AmericanOdds.ev_over(p: prob_over, american_odds: odds)

      decision_score = PlayerProps::DecisionScorer.call(
        model_score: computed,
        adjusted_probability: adj_p,
        ev: ev,
        context_modifier_total: adj[:modifier_total],
        coefficient_of_variation: h['coefficient_of_variation']
      )

      core.merge!(
        analysis_mode: 'points_props_pro',
        manual_game_context: manual_json,
        injuries: manual[:injuries],
        returning_players: manual[:returning_players],
        opponent_defense_rank_vs_position: manual[:opponent_defense_rank_vs_position],
        opponent_rebounds_allowed_rank: manual[:opponent_rebounds_allowed_rank],
        pace: manual[:pace],
        is_back_to_back: manual[:is_back_to_back],
        is_home: manual[:is_home],
        spread: spread_val,
        probability_over: prob_over.round(4),
        implied_probability: implied&.round(4),
        ev: ev&.round(4),
        ev_base: ev_base&.round(4),
        adjusted_probability: adj_p.round(4),
        context_modifier_total: adj[:modifier_total].round(4),
        context_modifiers_applied: adj[:modifiers],
        probability_over_percent: (prob_over * 100).round(2),
        implied_probability_percent: implied ? (implied * 100).round(2) : nil,
        adjusted_probability_percent: (adj_p * 100).round(2),
        context_modifier_total_percent_points: (adj[:modifier_total] * 100).round(2),
        decision_score: decision_score
      )

      core.compact
    end

    def self.merge_opponent_context!(input, game:, player:, opponent:)
      opp_abbr = opponent.to_s.strip.upcase
      input[:game_context] = (input[:game_context] || {}).merge(
        'home_team' => game.home_team,
        'away_team' => game.away_team,
        'game_date' => game.game_date&.to_s,
        'opponent_team_abbr' => opponent
      ).compact

      return input if opp_abbr.blank?

      split = player.player_opponent_splits.find_by(season: Nba::Season.current, opponent_team: opp_abbr)
      if split
        input[:opponent_split] = {
          'gp' => split.gp,
          'avg_points' => split.avg_points&.to_f,
          'avg_rebounds' => split.avg_rebounds&.to_f,
          'avg_assists' => split.avg_assists&.to_f,
          'avg_minutes' => split.avg_minutes&.to_f,
          'avg_fgm' => split.avg_fgm&.to_f,
          'avg_fga' => split.avg_fga&.to_f,
          'avg_three_pt_made' => split.avg_three_pt_made&.to_f,
          'avg_three_pt_attempted' => split.avg_three_pt_attempted&.to_f
        }.compact
      end

      team_row = TeamSeasonStat.find_by(season: Nba::Season.current, team_abbr: opp_abbr)
      if team_row
        input[:opponent_team_stats] = {
          'team_abbr' => team_row.team_abbr,
          'gp' => team_row.gp,
          'pts' => team_row.pts&.to_f,
          'reb' => team_row.reb&.to_f,
          'ast' => team_row.ast&.to_f,
          'fgm' => team_row.fgm&.to_f,
          'fga' => team_row.fga&.to_f,
          'fg3m' => team_row.fg3m&.to_f,
          'fg3a' => team_row.fg3a&.to_f,
          'fg_pct' => team_row.fg_pct&.to_f,
          'fg3_pct' => team_row.fg3_pct&.to_f
        }.compact
      end

      input
    end
  end
end
