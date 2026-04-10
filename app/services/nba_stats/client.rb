require 'httparty'

module NbaStats
  class Client
    include HTTParty
    base_uri 'https://stats.nba.com/stats'

    NBA_HEADERS = {
      'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer' => 'https://www.nba.com/',
      'Accept' => 'application/json, text/plain, */*',
      'Accept-Language' => 'en-US,en;q=0.9'
    }.freeze

    def self.player_game_log(player_id:, season:)
      new.player_game_log(player_id: player_id, season: season)
    end

    def player_game_log(player_id:, season:)
      query = {
        PlayerID: player_id,
        Season: season,
        SeasonType: 'Regular Season',
        LeagueID: '00'
      }
      HttpClient.with_retry do
        self.class.get('/playergamelog', query: query, headers: NBA_HEADERS, timeout: 30)
      end
    end

    def self.scoreboard(game_date:)
      query = {
        GameDate: game_date,
        LeagueID: '00',
        DayOffset: 0
      }
      HttpClient.with_retry do
        get('/scoreboardv2', query: query, headers: NBA_HEADERS, timeout: 45)
      end
    end
  end
end
