module NbaStats
  # Upserts games for a single calendar day (NBA scoreboard for that date only).
  class ScoreboardSync
    Result = Struct.new(:ok, :games_count, :error, keyword_init: true) do
      def success?
        ok
      end
    end

    def self.call(date: Date.current)
      new(date: date).call
    end

    def initialize(date:)
      @date = date
    end

    def call
      formatted = @date.strftime('%m/%d/%Y')
      response = Client.scoreboard(game_date: formatted)
      unless response.success?
        return Result.new(ok: false, games_count: 0, error: "NBA scoreboard HTTP #{response.code}")
      end

      body = response.parsed_response
      sets = body['resultSets'] || []
      header = sets.find { |s| s['name'] == 'GameHeader' }
      line_score = sets.find { |s| s['name'] == 'LineScore' }
      return Result.new(ok: false, games_count: 0, error: 'Scoreboard payload incompleto') unless header && line_score

      h = header['headers']
      game_rows = header['rowSet'] || []
      idx_h = ->(name) { h.index(name) }

      lh = line_score['headers']
      ls_rows = line_score['rowSet'] || []
      idx_l = ->(name) { lh.index(name) }

      gid_h = idx_h.call('GAME_ID')
      home_id_h = idx_h.call('HOME_TEAM_ID')
      vis_id_h = idx_h.call('VISITOR_TEAM_ID')
      date_h = idx_h.call('GAME_DATE_EST')
      status_h = idx_h.call('GAME_STATUS_TEXT')

      gid_l = idx_l.call('GAME_ID')
      tid_l = idx_l.call('TEAM_ID')
      abb_l = idx_l.call('TEAM_ABBREVIATION')

      return Result.new(ok: false, games_count: 0, error: 'Colunas da NBA mudaram — ajuste o parser') if [gid_h, home_id_h, vis_id_h, gid_l, tid_l, abb_l].any?(&:nil?)

      by_game = ls_rows.group_by { |r| r[gid_l] }
      count = 0

      ActiveRecord::Base.transaction do
        game_rows.each do |row|
          gid = row[gid_h].to_s
          next if gid.blank?

          home_id = row[home_id_h]
          vis_id = row[vis_id_h]
          rows = by_game[row[gid_h]] || []
          home_row = rows.find { |r| r[tid_l] == home_id }
          vis_row = rows.find { |r| r[tid_l] == vis_id }
          next unless home_row && vis_row

          game_date = parse_date(row[date_h]) || @date
          status_text = status_h ? row[status_h].to_s.strip : ''

          record = Game.find_or_initialize_by(nba_game_id: gid)
          record.assign_attributes(
            home_team: home_row[abb_l].to_s,
            away_team: vis_row[abb_l].to_s,
            game_date: game_date,
            status: status_text.presence || 'scheduled'
          )
          record.save!
          count += 1
        end
      end

      Result.new(ok: true, games_count: count, error: nil)
    rescue StandardError => e
      Rails.logger.error("[ScoreboardSync] #{e.class}: #{e.message}")
      Result.new(ok: false, games_count: 0, error: e.message)
    end

    private

    def parse_date(value)
      return if value.blank?

      Date.parse(value.to_s.split('T').first)
    rescue ArgumentError
      nil
    end

  end
end
