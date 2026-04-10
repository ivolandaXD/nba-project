# Importa playercareerstats para todos os Player com nba_player_id (pode levar vários minutos).
class PlayerSeasonStatsSyncJob < ApplicationJob
  queue_as :default

  def perform(season = nil)
    season = season.presence || Nba::Season.current
    result = NbaStats::PlayerSeasonStatsSync.call(season: season, limit: nil)
    Rails.logger.info("[PlayerSeasonStatsSyncJob] season=#{season} synced=#{result.synced_count} error_lines=#{result.errors.size}")
    result.errors.first(30).each { |e| Rails.logger.warn("[PlayerSeasonStatsSyncJob] #{e}") }
    result
  end
end
