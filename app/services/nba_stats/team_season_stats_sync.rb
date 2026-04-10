module NbaStats
  # Importa médias por jogo por time (leaguedashteamstats) para team_season_stats.
  class TeamSeasonStatsSync
    Result = Struct.new(:ok, :synced_count, :errors, keyword_init: true) do
      def success?
        ok
      end
    end

    def self.call(season: Nba::Season.current)
      new(season: season).call
    end

    def initialize(season:)
      @season = season.to_s.strip
    end

    def call
      errors = []
      response = Client.league_dash_team_stats(season: @season, per_mode: 'PerGame', measure_type: 'Base')
      unless response.success?
        return Result.new(ok: false, synced_count: 0, errors: ["HTTP #{response.code}"])
      end

      body = response.parsed_response
      unless body.is_a?(Hash)
        return Result.new(ok: false, synced_count: 0, errors: ['JSON inválido'])
      end

      set = (body['resultSets'] || []).find { |s| s['name'].to_s == 'LeagueDashTeamStats' }
      unless set
        return Result.new(ok: false, synced_count: 0, errors: ['sem LeagueDashTeamStats'])
      end

      headers = normalize_stat_headers(set['headers'])
      rows = set['rowSet'] || []
      if rows.empty?
        return Result.new(ok: false, synced_count: 0, errors: ['LeagueDashTeamStats sem linhas'])
      end

      unless team_abbr_from_row(rows.first, headers).present?
        preview = headers.first(25).join(', ')
        return Result.new(
          ok: false,
          synced_count: 0,
          errors: ["não foi possível resolver abreviação do time (TEAM_ABBREVIATION/TEAM_ID). Colunas: #{preview}"]
        )
      end

      i_name = header_column_index(headers, 'TEAM_NAME')

      pace_by_abbr = fetch_pace_by_abbr

      synced = 0
      rows.each do |row|
        abbr = team_abbr_from_row(row, headers)
        next if abbr.blank?

        abbr = abbr.to_s.strip.upcase
        h = row_to_hash(headers, row)
        rec = TeamSeasonStat.find_or_initialize_by(season: @season, team_abbr: abbr)
        rec.assign_attributes(
          team_name: i_name ? row[i_name].to_s.presence : nil,
          gp: pick_int(h, %w[GP]),
          w: pick_int(h, %w[W]),
          l: pick_int(h, %w[L]),
          min: pick_dec(h, %w[MIN]),
          pts: pick_dec(h, %w[PTS]),
          reb: pick_dec(h, %w[REB]),
          ast: pick_dec(h, %w[AST]),
          stl: pick_dec(h, %w[STL]),
          blk: pick_dec(h, %w[BLK]),
          tov: pick_dec(h, %w[TOV]),
          oreb: pick_dec(h, %w[OREB]),
          dreb: pick_dec(h, %w[DREB]),
          fgm: pick_dec(h, %w[FGM]),
          fga: pick_dec(h, %w[FGA]),
          fg_pct: pick_dec(h, %w[FG_PCT]),
          fg3m: pick_dec(h, %w[FG3M]),
          fg3a: pick_dec(h, %w[FG3A]),
          fg3_pct: pick_dec(h, %w[FG3_PCT]),
          ftm: pick_dec(h, %w[FTM]),
          fta: pick_dec(h, %w[FTA]),
          ft_pct: pick_dec(h, %w[FT_PCT]),
          pace: pace_by_abbr[abbr.upcase],
          per_game_row: h.stringify_keys,
          synced_at: Time.current
        )
        rec.save!
        synced += 1
      rescue StandardError => e
        errors << "#{abbr}: #{e.message}"
      end

      Result.new(ok: errors.empty? || synced.positive?, synced_count: synced, errors: errors)
    end

    private

    def fetch_pace_by_abbr
      rsp = Client.league_dash_team_stats(season: @season, per_mode: 'PerGame', measure_type: 'Advanced')
      unless rsp.success?
        DataIngestion::Logger.log('TeamSeasonStats', level: :warn, message: 'PACE Advanced indisponível', code: rsp.code)
        return {}
      end

      body = rsp.parsed_response
      set = (body['resultSets'] || []).find { |s| s['name'].to_s == 'LeagueDashTeamStats' }
      return {} unless set

      headers = normalize_stat_headers(set['headers'])
      rows = set['rowSet'] || []
      i_pace = header_column_index(headers, 'PACE', 'Pace')
      return {} if i_pace.nil?

      rows.each_with_object({}) do |row, acc|
        ab = team_abbr_from_row(row, headers)
        next if ab.blank?

        ab = ab.to_s.strip.upcase

        raw = row[i_pace]
        next if raw.nil? || raw == ''

        acc[ab] = BigDecimal(raw.to_s).round(3)
      end
    rescue StandardError => e
      DataIngestion::Logger.log('TeamSeasonStats', level: :warn, message: "PACE: #{e.message}")
      {}
    end

    def normalize_stat_headers(raw)
      Array(raw).map { |h| h.to_s.strip }
    end

    def header_column_index(headers, *candidates)
      candidates.each do |cand|
        headers.each_with_index do |h, i|
          return i if h.casecmp(cand).zero?
        end
      end
      nil
    end

    def team_abbr_from_row(row, headers)
      ia = header_column_index(headers, 'TEAM_ABBREVIATION', 'TEAM_ABB')
      if ia
        v = row[ia].to_s.strip.presence
        return v if v.present?
      end

      tid_i = header_column_index(headers, 'TEAM_ID')
      if tid_i && row.size > tid_i
        id = row[tid_i].to_i
        ab = NbaStats::TeamCodes::TEAM_ID_TO_ABBR[id]
        return ab if ab.present?
      end

      nil
    end

    def row_to_hash(headers, row)
      headers.each_with_index.with_object({}) do |(name, i), acc|
        acc[name] = row[i] if i < row.size
      end
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
