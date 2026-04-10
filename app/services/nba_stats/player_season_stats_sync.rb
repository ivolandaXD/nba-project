# frozen_string_literal: true

module NbaStats
  # Importa médias da temporada: stats.nba.com primeiro; fallback balldontlie.io.
  class PlayerSeasonStatsSync
    Result = Struct.new(:ok, :synced_count, :errors, keyword_init: true) do
      def success?
        ok
      end
    end

    def self.call(season: Nba::Season.current, limit: nil, player_ids: nil)
      scope = Player.where('nba_player_id IS NOT NULL OR bdl_player_id IS NOT NULL').order(:id)
      scope = scope.where(id: player_ids) if player_ids.present?
      scope = scope.limit(limit) if limit.present?
      new(season: season, scope: scope).call
    end

    def initialize(season:, scope:)
      @season = season.to_s.strip
      @scope = scope
    end

    def call
      errors = []
      synced = 0
      delay = ENV.fetch('NBA_SEASON_SYNC_DELAY_SEC', 0.35).to_f

      @scope.find_each do |player|
        r = sync_player(player)
        if r[:ok]
          synced += 1
        else
          errors << "#{player.name}: #{r[:error]}"
        end
        sleep(delay) if delay.positive?
      end

      Result.new(ok: errors.empty? || synced.positive?, synced_count: synced, errors: errors)
    end

    def sync_player(player)
      pid = player.nba_player_id
      rec = PlayerSeasonStat.find_or_initialize_by(player_id: player.id, season: @season)

      nba_row = pid.present? ? fetch_nba_row(pid) : nil
      if nba_row.present?
        apply_nba_row!(rec, player, nba_row)
        maybe_audit_bdl(player)
        return { ok: true, error: nil }
      end

      if rec.persisted? && rec.data_source == DataSourceTrackable::SOURCE_NBA
        msg = 'NBA indisponível ou temporada ausente; mantendo linha existente (fonte NBA).'
        DataIngestion::Logger.log('PlayerSeasonStats', level: :warn, message: msg, player_id: player.id)
        return { ok: false, error: msg }
      end

      agg = Balldontlie::PlayerSeasonAggregator.call(player, season: @season)
      if agg.blank?
        return { ok: false, error: "temporada #{@season} não encontrada (NBA) e balldontlie vazio" }
      end

      rec.assign_attributes(
        team_abbr: player.team,
        gp: agg[:gp],
        min: agg[:min],
        pts: agg[:pts],
        reb: agg[:reb],
        ast: agg[:ast],
        stl: agg[:stl],
        blk: agg[:blk],
        tov: agg[:tov],
        fgm: agg[:fgm],
        fga: agg[:fga],
        fg3m: agg[:fg3m],
        fg3a: agg[:fg3a],
        fg_pct: nil,
        fg3_pct: nil,
        ft_pct: nil,
        per_game_row: agg[:per_game_row].stringify_keys,
        synced_at: Time.current,
        data_source: DataSourceTrackable::SOURCE_BALLDONTLIE
      )
      rec.save!
      DataIngestion::Logger.log(
        'PlayerSeasonStats',
        message: 'fonte balldontlie',
        player_id: player.id,
        season: @season
      )
      { ok: true, error: nil }
    rescue StandardError => e
      Rails.logger.error("[PlayerSeasonStatsSync] #{e.class}: #{e.message}")
      { ok: false, error: e.message }
    end

    private

    def fetch_nba_row(player_nba_id)
      return nil if player_nba_id.blank?

      response = Client.player_career_stats(player_id: player_nba_id, per_mode: 'PerGame')
      unless response.success?
        DataIngestion::Logger.log(
          'PlayerSeasonStats',
          level: :warn,
          message: 'NBA HTTP falhou',
          code: response.code
        )
        return nil
      end

      body = response.parsed_response
      return nil unless body.is_a?(Hash)

      extract_season_row(body, @season)
    end

    def apply_nba_row!(rec, player, row_hash)
      rec.assign_attributes(
        team_abbr: pick_str(row_hash, %w[TEAM_ABBREVIATION TEAM_ABBREV TEAM]).presence || player.team,
        gp: pick_int(row_hash, %w[GP]),
        min: pick_dec(row_hash, %w[MIN]),
        pts: pick_dec(row_hash, %w[PTS]),
        reb: pick_dec(row_hash, %w[REB REBOUNDS]),
        ast: pick_dec(row_hash, %w[AST]),
        stl: pick_dec(row_hash, %w[STL]),
        blk: pick_dec(row_hash, %w[BLK]),
        tov: pick_dec(row_hash, %w[TOV]),
        fgm: pick_dec(row_hash, %w[FGM]),
        fga: pick_dec(row_hash, %w[FGA]),
        fg3m: pick_dec(row_hash, %w[FG3M]),
        fg3a: pick_dec(row_hash, %w[FG3A]),
        fg_pct: pick_dec(row_hash, %w[FG_PCT]),
        fg3_pct: pick_dec(row_hash, %w[FG3_PCT]),
        ft_pct: pick_dec(row_hash, %w[FT_PCT]),
        per_game_row: row_hash.stringify_keys,
        synced_at: Time.current,
        data_source: DataSourceTrackable::SOURCE_NBA
      )
      rec.save!
    end

    def maybe_audit_bdl(player)
      return unless ENV['NBA_CROSS_VALIDATE_BDL'] == '1'

      DataIngestion::CrossSourceValidator.audit_season_ppg(player, @season)
    end

    def extract_season_row(body, season)
      want = normalize_season_id(season)
      sets = body['resultSets'] || []

      sets.each do |target_set|
        headers = target_set['headers'] || []
        idx_season = headers.index('SEASON_ID')
        next unless idx_season

        rows = target_set['rowSet'] || []
        candidates = rows.select { |row| normalize_season_id(row[idx_season]) == want }
        next if candidates.empty?

        if candidates.size > 1
          h_gp = headers.index('GP')
          candidates = [h_gp ? candidates.max_by { |r| r[h_gp].to_i } : candidates.first]
        end

        return row_to_hash(headers, candidates.first)
      end

      nil
    end

    def normalize_season_id(val)
      val.to_s.strip.delete(' ')
    end

    def row_to_hash(headers, row)
      headers.each_with_index.with_object({}) do |(name, i), acc|
        acc[name] = row[i] if i < row.size
      end
    end

    def pick_str(h, keys)
      keys.each { |k| return h[k].to_s.presence if h.key?(k) }
      nil
    end

    def pick_int(h, keys)
      keys.each { |k| return h[k].to_i if h.key?(k) && h[k].present? }
      nil
    end

    def pick_dec(h, keys)
      keys.each do |k|
        next unless h.key?(k)
        v = h[k]
        return nil if v.nil? || v == ''
        return BigDecimal(v.to_s).round(3)
      end
      nil
    end
  end
end
