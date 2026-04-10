module NbaStats
  # Importa elenco da temporada via commonallplayers (stats.nba.com) e preenche players.nba_player_id.
  # Sem isso, PlayerSeasonStatsSync não processa ninguém se os IDs nunca foram gravados.
  class LeaguePlayersSync
    Result = Struct.new(:ok, :upserted_count, :linked_orphans_count, :errors, keyword_init: true) do
      def success?
        ok
      end
    end

    def self.call(season: Nba::Season.current, only_current_season: true, link_orphans: true)
      new(season: season, only_current_season: only_current_season, link_orphans: link_orphans).call
    end

    def initialize(season:, only_current_season:, link_orphans:)
      @season = season.to_s.strip
      @only_current_season = only_current_season
      @link_orphans = link_orphans
    end

    def call
      errors = []
      response = Client.common_all_players(season: @season, is_only_current_season: @only_current_season ? 1 : 0)
      unless response.success?
        return Result.new(ok: false, upserted_count: 0, linked_orphans_count: 0, errors: ["HTTP #{response.code}"])
      end

      body = response.parsed_response
      unless body.is_a?(Hash)
        return Result.new(ok: false, upserted_count: 0, linked_orphans_count: 0, errors: ['JSON inválido'])
      end

      set = (body['resultSets'] || []).find { |s| s['name'].to_s == 'CommonAllPlayers' }
      unless set
        return Result.new(ok: false, upserted_count: 0, linked_orphans_count: 0, errors: ['payload sem CommonAllPlayers'])
      end

      headers = set['headers'] || []
      rows = set['rowSet'] || []
      idx = ->(name) { headers.index(name) }

      i_pid = idx.call('PERSON_ID')
      i_name = idx.call('DISPLAY_FIRST_LAST')
      i_team = idx.call('TEAM_ABBREVIATION')
      if i_pid.nil? || i_name.nil?
        return Result.new(ok: false, upserted_count: 0, linked_orphans_count: 0, errors: ['colunas PERSON_ID / DISPLAY_FIRST_LAST ausentes'])
      end

      name_team_map = Hash.new { |h, k| h[k] = [] }
      upserted = 0

      rows.each do |row|
        nba_id = row[i_pid]
        next if nba_id.blank?

        name = row[i_name].to_s.strip
        next if name.blank?

        team_abbr = i_team ? row[i_team].to_s.strip.presence : nil

        rec = Player.find_or_initialize_by(nba_player_id: nba_id.to_i)
        rec.name = name
        rec.team = team_abbr if team_abbr.present? || rec.team.blank?
        rec.save!
        upserted += 1

        if team_abbr.present?
          key = [name.downcase, team_abbr.upcase]
          name_team_map[key] << nba_id.to_i unless name_team_map[key].include?(nba_id.to_i)
        end
      rescue StandardError => e
        label = row[i_name].to_s.presence || "id=#{row[i_pid]}"
        errors << "#{label}: #{e.message}"
      end

      linked = 0
      linked = link_orphans(name_team_map, errors) if @link_orphans

      Result.new(ok: errors.empty?, upserted_count: upserted, linked_orphans_count: linked, errors: errors)
    end

    private

    def link_orphans(name_team_map, errors)
      count = 0
      Player.where(nba_player_id: nil).find_each do |player|
        name = player.name.to_s.strip
        next if name.blank?

        team = player.team.to_s.strip.upcase
        next if team.blank?

        key = [name.downcase, team]
        ids = name_team_map[key]
        next unless ids.is_a?(Array) && ids.size == 1

        nid = ids.first
        next if Player.where(nba_player_id: nid).where.not(id: player.id).exists?

        player.update!(nba_player_id: nid)
        count += 1
      rescue StandardError => e
        errors << "link #{player.name}: #{e.message}"
      end
      count
    end
  end
end
