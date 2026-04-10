require 'httparty'

module NbaStats
  class Client
    include HTTParty
    base_uri 'https://stats.nba.com/stats'

    NBA_HEADERS = {
      'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer' => 'https://www.nba.com/',
      'Origin' => 'https://www.nba.com',
      'Accept' => 'application/json, text/plain, */*',
      'Accept-Language' => 'en-US,en;q=0.9'
    }.freeze

    SCOREBOARD_OPEN_TIMEOUT = ENV.fetch('NBA_SCOREBOARD_OPEN_TIMEOUT', 30).to_i
    SCOREBOARD_READ_TIMEOUT = ENV.fetch('NBA_SCOREBOARD_READ_TIMEOUT', 180).to_i

    def self.player_game_log(player_id:, season:)
      new.player_game_log(player_id: player_id, season: season)
    end

    def self.common_all_players(season:, is_only_current_season: 1)
      query = {
        LeagueID: '00',
        Season: season,
        IsOnlyCurrentSeason: is_only_current_season
      }
      HttpClient.with_retry(attempts: 3, base_sleep: 1.0) do
        get(
          '/commonallplayers',
          query: query,
          headers: NBA_HEADERS,
          open_timeout: 20,
          read_timeout: 90
        )
      end
    end

    def self.player_career_stats(player_id:, per_mode: 'PerGame')
      query = {
        PlayerID: player_id,
        PerMode: per_mode,
        LeagueID: '00'
      }
      HttpClient.with_retry(attempts: 3, base_sleep: 1.0) do
        get(
          '/playercareerstats',
          query: query,
          headers: NBA_HEADERS,
          open_timeout: 20,
          read_timeout: 90
        )
      end
    end

    def player_game_log(player_id:, season:)
      query = {
        PlayerID: player_id,
        Season: season,
        SeasonType: 'Regular Season',
        LeagueID: '00'
      }
      HttpClient.with_retry do
        self.class.get(
          '/playergamelog',
          query: query,
          headers: NBA_HEADERS,
          open_timeout: 20,
          read_timeout: 60
        )
      end
    end

    def self.scoreboard(game_date:)
      query = {
        GameDate: game_date,
        LeagueID: '00',
        DayOffset: 0
      }
      HttpClient.with_retry(attempts: 3, base_sleep: 1.5) do
        get(
          '/scoreboardv2',
          query: query,
          headers: NBA_HEADERS,
          open_timeout: SCOREBOARD_OPEN_TIMEOUT,
          read_timeout: SCOREBOARD_READ_TIMEOUT
        )
      end
    end

    # Médias por jogo da liga por time (Base = PTS, REB, FGM, FGA, FG3M, FG3A, etc.).
    def self.league_dash_team_stats(season:, per_mode: 'PerGame', measure_type: 'Base')
      query = {
        College: '',
        Conference: '',
        Country: '',
        DateFrom: '',
        DateTo: '',
        Division: '',
        DraftPick: '',
        DraftYear: '',
        GameScope: '',
        GameSegment: '',
        Height: '',
        LastNGames: 0,
        LeagueID: '00',
        Location: '',
        MeasureType: measure_type,
        Month: 0,
        OpponentTeamID: 0,
        Outcome: '',
        PORound: 0,
        PaceAdjust: 'N',
        PerMode: per_mode,
        Period: 0,
        PlayerExperience: '',
        PlayerPosition: '',
        PlusMinus: 'N',
        Rank: 'N',
        Season: season,
        SeasonSegment: '',
        SeasonType: 'Regular Season',
        ShotClockRange: '',
        StarterBench: '',
        TeamID: 0,
        TwoWay: 0,
        VsConference: '',
        VsDivision: ''
      }
      HttpClient.with_retry(attempts: 3, base_sleep: 1.0) do
        get(
          '/leaguedashteamstats',
          query: query,
          headers: NBA_HEADERS,
          open_timeout: 25,
          read_timeout: 120
        )
      end
    end
  end
end
