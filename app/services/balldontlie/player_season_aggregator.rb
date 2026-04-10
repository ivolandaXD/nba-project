# frozen_string_literal: true

module Balldontlie
  # Agrega médias por jogo a partir de /stats (fonte secundária).
  class PlayerSeasonAggregator
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
      return nil unless bdl_id.present?

      rows = StatsFetcher.all_stats(bdl_player_id: bdl_id, season_int: @bdl_season)
      return nil if rows.empty?

      gp = 0
      sums = Hash.new(0.0)
      rows.each do |st|
        next if st['pts'].nil? && st['min'].nil?

        gp += 1
        sums[:pts] += st['pts'].to_f
        sums[:reb] += st['reb'].to_f
        sums[:ast] += st['ast'].to_f
        sums[:stl] += st['stl'].to_f
        sums[:blk] += st['blk'].to_f
        sums[:tov] += st['turnover'].to_f
        sums[:fgm] += st['fgm'].to_f
        sums[:fga] += st['fga'].to_f
        sums[:fg3m] += st['fg3m'].to_f
        sums[:fg3a] += st['fg3a'].to_f
        sums[:min] += parse_minutes(st['min']).to_f
      end

      return nil if gp <= 0

      {
        gp: gp,
        pts: (sums[:pts] / gp).round(2),
        reb: (sums[:reb] / gp).round(2),
        ast: (sums[:ast] / gp).round(2),
        stl: (sums[:stl] / gp).round(2),
        blk: (sums[:blk] / gp).round(2),
        tov: (sums[:tov] / gp).round(2),
        fgm: (sums[:fgm] / gp).round(2),
        fga: (sums[:fga] / gp).round(2),
        fg3m: (sums[:fg3m] / gp).round(2),
        fg3a: (sums[:fg3a] / gp).round(2),
        min: (sums[:min] / gp).round(2),
        per_game_row: { 'source' => 'balldontlie', 'gp' => gp, 'season_int' => @bdl_season }
      }
    end

    private

    def parse_minutes(raw)
      return 0.0 if raw.blank?

      if raw.to_s.include?(':')
        m, s = raw.to_s.split(':').map(&:to_f)
        m + (s / 60.0)
      else
        raw.to_f
      end
    end
  end
end
