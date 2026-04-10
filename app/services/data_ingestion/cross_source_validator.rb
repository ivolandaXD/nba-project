# frozen_string_literal: true

module DataIngestion
  # Compara métricas locais (NBA) com balldontlie quando ambos existem — só log.
  class CrossSourceValidator
    def self.audit_season_ppg(player, season)
      local = player.player_season_stats.find_by(season: season.to_s.strip)
      return if local.blank? || local.pts.blank?
      return unless local.data_source == DataSourceTrackable::SOURCE_NBA

      bdl_avg = Balldontlie::PlayerSeasonAggregator.call(player, season: season)&.dig(:pts)
      return if bdl_avg.blank?

      diff = (local.pts.to_f - bdl_avg.to_f).abs
      return if diff <= ENV.fetch('NBA_CROSS_VALIDATE_PPG_THRESHOLD', 2.5).to_f

      DataIngestion::Logger.log(
        'CrossSource',
        level: :warn,
        message: 'PPG divergente NBA vs balldontlie',
        player_id: player.id,
        season: season,
        local_ppg: local.pts.to_f,
        bdl_ppg: bdl_avg,
        diff: diff.round(2)
      )
    end
  end
end
