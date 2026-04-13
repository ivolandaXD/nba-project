# frozen_string_literal: true

module Ai
  # Exporta JSON com o mesmo contexto que o app monta para a OpenAI (portfólio + prompts de sistema),
  # para análise offline (ex.: colar no chat e pedir ~20 ideias de props sem chamar a API).
  class GamePayloadExporter
    Result = Struct.new(:ok, :path, :json, :error, keyword_init: true) do
      def success?
        ok
      end
    end

    def self.call(game_id:, player_limit: 20, output_path: nil)
      new(game_id: game_id, player_limit: player_limit, output_path: output_path).call
    end

    def initialize(game_id:, player_limit:, output_path:)
      @game_id = game_id.to_i
      @player_limit = [player_limit.to_i, 1].max
      @output_path = output_path.presence
    end

    def call
      game = Game.find(@game_id)
      season = Nba::Season.current
      roster = GameRoster.new(game: game, season: season)
      players = pick_players(game, roster, season)

      home_row = TeamSeasonStat.find_by(season: season, team_abbr: roster.home_abbr)
      away_row = TeamSeasonStat.find_by(season: season, team_abbr: roster.away_abbr)

      odds = OddsSnapshot.where(game_id: game.id).includes(:player).order(:market_type, :player_id, :id)

      export = {
        export_version: 1,
        how_to_use: 'Cole este JSON (ou o ficheiro) no chat e peça ~20 opções de apostas (props) coerentes com os dados; use openai.system_prompts.pregame_portfolio como regras de resposta em JSON.',
        generated_at: Time.current.utc.iso8601,
        season: season,
        game: game_summary(game, roster),
        team_season_stats: {
          home: team_row_json(home_row, roster.home_abbr),
          away: team_row_json(away_row, roster.away_abbr)
        },
        odds_snapshots: odds.map { |o| odds_snapshot_json(o) },
        openai: openai_meta,
        players: players.map { |p| player_block(game, p, season) }
      }

      pi = PlayIn2026Context.matchup_for_game(game)
      export[:external_game_context] = PlayIn2026Context.build_package_hash(pi, game) if pi

      json = JSON.pretty_generate(export)
      File.write(@output_path, json) if @output_path

      Result.new(ok: true, path: @output_path, json: json, error: nil)
    rescue ActiveRecord::RecordNotFound => e
      Result.new(ok: false, path: nil, json: nil, error: e.message)
    rescue StandardError => e
      Result.new(ok: false, path: nil, json: nil, error: "#{e.class}: #{e.message}")
    end

    private

    def pick_players(game, roster, season)
      all = roster.all_players.to_a
      return all.first(@player_limit) if all.size <= @player_limit

      ids = all.map(&:id)
      pss = PlayerSeasonStat.where(season: season, player_id: ids).index_by(&:player_id)
      all.sort_by do |pl|
        pts = pss[pl.id]&.pts&.to_f
        pts.nil? ? -1.0 : -pts
      end.first(@player_limit)
    end

    def game_summary(game, roster)
      {
        id: game.id,
        game_date: game.game_date&.to_s,
        home_team: game.home_team,
        away_team: game.away_team,
        normalized_home_abbr: roster.home_abbr,
        normalized_away_abbr: roster.away_abbr,
        status: game.status,
        home_win_prob: game.home_win_prob&.to_f,
        away_win_prob: game.away_win_prob&.to_f
      }.compact
    end

    def team_row_json(row, abbr)
      return { team_abbr: abbr, synced: false } if row.nil?

      {
        team_abbr: row.team_abbr,
        gp: row.gp,
        pts: row.pts&.to_f,
        reb: row.reb&.to_f,
        ast: row.ast&.to_f,
        pace: row.pace&.to_f,
        fg_pct: row.fg_pct&.to_f,
        fg3_pct: row.fg3_pct&.to_f
      }.compact
    end

    def odds_snapshot_json(o)
      {
        id: o.id,
        market_type: o.market_type,
        line: o.line&.to_f,
        odds: o.odds,
        source: o.source,
        player_id: o.player_id,
        player_name: o.player&.name
      }.compact
    end

    def openai_meta
      {
        user_message_prefix: "Dados JSON:\n",
        note: 'No app (OpenAiAnalyzer), messages = system: PromptCatalog conforme analysis_mode + user: prefixo + JSON do input. Modo portfólio = pregame_portfolio (vários mercados por jogador).',
        system_prompts: {
          pregame_portfolio: Ai::PromptCatalog.pregame_portfolio_system,
          pregame_single_market_pro: Ai::PromptCatalog.pregame_single_market_pro_system,
          pregame_single_market_legacy: Ai::PromptCatalog.pregame_single_market_legacy_system,
          postgame_review: Ai::PromptCatalog.postgame_review_system,
          protocol_prefix: Ai::PromptCatalog.protocol_prefix
        }
      }
    end

    def player_block(game, player, season)
      opp_abbr = opponent_abbr_for(game, player)
      primary = PlayerMetrics::Calculator.cached_payload(
        player,
        stat_key: :points,
        line: nil,
        opponent_team: opp_abbr
      )
      computed = PlayerMetrics::ConfidenceScorer.call(primary[:scorer_inputs])

      prop_focus = Ai::GamePlayerAnalysis.normalize_prop_focus(%w[all], 'points')
      input = Ai::GamePlayerAnalysis.build_portfolio_input(
        game: game,
        player: player,
        opponent: opp_abbr,
        prop_focus: prop_focus,
        primary_stat: :points,
        line_val: nil,
        odds: nil,
        computed: computed,
        user_note: nil,
        params: {}
      )
      Ai::GamePlayerAnalysis.merge_opponent_context!(input, game: game, player: player, opponent: opp_abbr)

      pss = PlayerSeasonStat.find_by(season: season, player_id: player.id)

      {
        player: { id: player.id, name: player.name, team: player.team },
        opponent_abbr: opp_abbr,
        season_totals_hint: pss ? { gp: pss.gp, pts: pss.pts&.to_f, reb: pss.reb&.to_f, ast: pss.ast&.to_f, team_abbr: pss.team_abbr } : nil,
        confidence_score_model: computed,
        portfolio_input: input.deep_stringify_keys,
        openai_user_message_body: JSON.pretty_generate(input.deep_stringify_keys)
      }.compact
    end

    # Resolve adversário por elenco normalizado (GS↔GSW) quando `opponent_team_for` falha por string cru.
    def opponent_abbr_for(game, player)
      season = Nba::Season.current
      gr = GameRoster.new(game: game, season: season)
      ht = gr.home_abbr
      at = gr.away_abbr
      pt = GameRoster.normalize_abbr(player.team)

      abbr =
        if pt.present? && pt == ht
          at
        elsif pt.present? && pt == at
          ht
        end

      if abbr.blank?
        raw = Ai::GamePlayerAnalysis.opponent_team_for(player, game)
        abbr = GameRoster.normalize_abbr(raw) if raw.present?
      end

      NbaStats::OpponentInferrer.canonical_abbr(abbr.to_s).presence
    end
  end
end
