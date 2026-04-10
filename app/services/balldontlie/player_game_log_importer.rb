# frozen_string_literal: true

module Balldontlie
  class PlayerGameLogImporter
    Result = Struct.new(:ok, :stats_count, :error, keyword_init: true) do
      def success?
        ok
      end
    end

    def self.call(player, season: Nba::Season.current)
      new(player, season: season).call
    end

    def initialize(player, season:)
      @player = player
      @season = season.to_s
      @bdl_season = Nba::Season.balldontlie_season_int(@season)
    end

    def call
      bdl_id = PlayerResolver.call(@player)
      unless bdl_id.present?
        return Result.new(ok: false, stats_count: 0, error: 'bdl_player_id não resolvido')
      end

      rows = fetch_all_stats(bdl_id)
      if rows.empty?
        DataIngestion::Logger.log('Balldontlie::GameLog', level: :warn, message: 'stats vazias', player_id: @player.id)
        return Result.new(ok: false, stats_count: 0, error: 'balldontlie stats vazias')
      end

      count = 0
      ActiveRecord::Base.transaction do
        rows.each do |st|
          game = st['game']
          next unless game.is_a?(Hash)

          gid = game['id']
          next if gid.blank?

          game_date = parse_date(game['date'])
          next unless game_date

          home = game.dig('home_team', 'abbreviation').to_s.strip.upcase
          visitor = game.dig('visitor_team', 'abbreviation').to_s.strip.upcase
          next if home.blank? || visitor.blank?

          team_abbr = @player.team.to_s.strip.upcase
          is_home = team_abbr.present? && home == team_abbr
          opponent = is_home ? visitor : home

          g = Game.find_or_initialize_by(nba_game_id: "bdl-#{gid}")
          if g.new_record?
            if is_home
              g.assign_attributes(home_team: home, away_team: visitor, game_date: game_date, status: 'final')
            else
              g.assign_attributes(home_team: home, away_team: visitor, game_date: game_date, status: 'final')
            end
            g.save!
          end

          stat = PlayerGameStat.find_or_initialize_by(player: @player, game: g)
          if stat.persisted? && stat.data_source == DataSourceTrackable::SOURCE_NBA
            next
          end

          stat.assign_attributes(
            game_date: game_date,
            opponent_team: opponent,
            is_home: is_home,
            minutes: parse_minutes(st['min']),
            points: int_or_nil(st['pts']),
            assists: int_or_nil(st['ast']),
            rebounds: int_or_nil(st['reb']),
            steals: int_or_nil(st['stl']),
            blocks: int_or_nil(st['blk']),
            turnovers: int_or_nil(st['turnover']),
            fgm: int_or_nil(st['fgm']),
            fga: int_or_nil(st['fga']),
            fg_pct: dec_or_nil(st['fg_pct']),
            three_pt_made: int_or_nil(st['fg3m']),
            three_pt_attempted: int_or_nil(st['fg3a']),
            three_pt_pct: dec_or_nil(st['fg3_pct']),
            ftm: int_or_nil(st['ftm']),
            fta: int_or_nil(st['fta']),
            ft_pct: dec_or_nil(st['ft_pct']),
            data_source: DataSourceTrackable::SOURCE_BALLDONTLIE
          )
          stat.save!
          count += 1
        end
      end

      DataIngestion::Logger.log(
        'Balldontlie::GameLog',
        message: 'import concluído',
        player_id: @player.id,
        stats_count: count,
        source: DataSourceTrackable::SOURCE_BALLDONTLIE
      )
      Result.new(ok: true, stats_count: count, error: nil)
    rescue StandardError => e
      Rails.logger.error("[Balldontlie::PlayerGameLogImporter] #{e.class}: #{e.message}")
      Result.new(ok: false, stats_count: 0, error: e.message)
    end

    private

    def fetch_all_stats(bdl_id)
      StatsFetcher.all_stats(bdl_player_id: bdl_id, season_int: @bdl_season)
    end

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

    def int_or_nil(v)
      return nil if v.nil? || v == ''

      v.to_i
    end

    def dec_or_nil(v)
      return nil if v.nil? || v == ''

      BigDecimal(v.to_s).round(3)
    end
  end
end
