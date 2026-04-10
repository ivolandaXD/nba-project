module NbaStats
  class PlayerGameLogImporter
    Result = Struct.new(:ok, :stats_count, :error, keyword_init: true) do
      def success?
        ok
      end
    end

    def self.call(player, season: ENV.fetch('NBA_SEASON', '2024-25'))
      new(player, season: season).call
    end

    def initialize(player, season:)
      @player = player
      @season = season
    end

    def call
      unless @player.nba_player_id.present?
        return Result.new(ok: false, stats_count: 0, error: 'Player nba_player_id is required')
      end

      response = Client.player_game_log(player_id: @player.nba_player_id, season: @season)
      unless response.success?
        return Result.new(ok: false, stats_count: 0, error: "NBA API error: HTTP #{response.code}")
      end

      body = response.parsed_response
      result_sets = body['resultSets'] || []
      log_set = result_sets.find { |rs| rs['name'] == 'PlayerGameLog' }
      return Result.new(ok: false, stats_count: 0, error: 'Unexpected NBA API payload') unless log_set

      headers = log_set['headers']
      rows = log_set['rowSet'] || []
      idx = ->(name) { headers.index(name) }

      count = 0
      ActiveRecord::Base.transaction do
        rows.each do |row|
          game_id = row[idx.call('Game_ID')]
          game_date = parse_date(row[idx.call('GAME_DATE')])
          next unless game_id && game_date

          matchup = row[idx.call('MATCHUP')].to_s
          is_home = matchup.include?(' vs. ')
          opponent_team = extract_opponent(matchup, @player.team)

          game = Game.find_or_initialize_by(nba_game_id: game_id.to_s)
          if game.new_record?
            home, away = infer_teams(matchup, @player.team, is_home)
            game.assign_attributes(
              game_date: game_date,
              home_team: home,
              away_team: away,
              status: 'final'
            )
            game.save!
          end

          stat = PlayerGameStat.find_or_initialize_by(player: @player, game: game)
          stat.assign_attributes(
            game_date: game_date,
            opponent_team: opponent_team,
            is_home: is_home,
            minutes: parse_minutes(row[idx.call('MIN')]),
            points: row[idx.call('PTS')],
            assists: row[idx.call('AST')],
            rebounds: row[idx.call('REB')],
            steals: row[idx.call('STL')],
            blocks: row[idx.call('BLK')],
            turnovers: row[idx.call('TOV')],
            fgm: row[idx.call('FGM')],
            fga: row[idx.call('FGA')],
            fg_pct: row[idx.call('FG_PCT')],
            three_pt_made: row[idx.call('FG3M')],
            three_pt_attempted: row[idx.call('FG3A')],
            three_pt_pct: row[idx.call('FG3_PCT')],
            ftm: row[idx.call('FTM')],
            fta: row[idx.call('FTA')],
            ft_pct: row[idx.call('FT_PCT')]
          )
          stat.save!
          count += 1
        end
      end

      Result.new(ok: true, stats_count: count, error: nil)
    rescue StandardError => e
      Rails.logger.error("[PlayerGameLogImporter] #{e.class}: #{e.message}")
      Result.new(ok: false, stats_count: 0, error: e.message)
    end

    private

    def parse_date(value)
      return if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_minutes(raw)
      return if raw.blank?

      if raw.to_s.include?(':')
        m, s = raw.to_s.split(':').map(&:to_f)
        m + (s / 60.0)
      else
        raw.to_f
      end
    end

    def extract_opponent(matchup, team_abbr)
      parts = matchup.split
      return parts.last if parts.size >= 3

      nil
    end

    def infer_teams(matchup, team_abbr, is_home)
      parts = matchup.gsub('@', ' @ ').split
      abbrs = parts.grep(/\A[A-Z]{2,3}\z/)
      opp = abbrs.find { |a| a != team_abbr } || abbrs.last
      if is_home
        [team_abbr, opp]
      else
        [opp, team_abbr]
      end
    end
  end
end
