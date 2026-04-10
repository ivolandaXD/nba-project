# frozen_string_literal: true

module NbaStats
  # Agrega player_game_stats por adversário (abbr) dentro do intervalo da temporada.
  # Implementação em Ruby + OpponentInferrer (is_home, opponent_team, aliases WSH/WAS, etc.).
  class PlayerOpponentSplitsRebuild
    Result = Struct.new(:ok, :rows_upserted, :error, :pgs_processed, :skipped_no_opp, keyword_init: true) do
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
      range = Nba::Season.date_range_for(@season)
      unless range
        return Result.new(ok: false, rows_upserted: 0, error: "temporada inválida: #{@season}", pgs_processed: nil,
                          skipped_no_opp: nil)
      end

      scope = PlayerGameStat
               .joins(:game, :player)
               .includes(:game, :player)
               .where(games: { game_date: range })

      bucket = Hash.new do |h, k|
        h[k] = {
          n: 0,
          minutes: 0.0,
          points: 0.0,
          rebounds: 0.0,
          assists: 0.0,
          steals: 0.0,
          blocks: 0.0,
          turnovers: 0.0,
          fgm: 0.0,
          fga: 0.0,
          thm: 0.0,
          tha: 0.0
        }
      end

      processed = 0
      skipped = 0
      roster_by_player = {}

      PlayerOpponentSplit.transaction do
        PlayerOpponentSplit.where(season: @season).delete_all

        scope.find_each(batch_size: 1_000) do |pgs|
          processed += 1
          game = pgs.game
          player = pgs.player
          pid = player.id
          unless roster_by_player.key?(pid)
            t = player.team.to_s.strip.presence
            t ||= PlayerSeasonStat.where(player_id: pid, season: @season).limit(1).pluck(:team_abbr).first
            roster_by_player[pid] = t
          end
          opp = OpponentInferrer.infer(pgs, game, player, roster_team: roster_by_player[pid])
          if opp.blank?
            skipped += 1
            next
          end

          key = [pgs.player_id, opp]
          b = bucket[key]
          b[:n] += 1
          b[:minutes] += pgs.minutes.to_f
          b[:points] += pgs.points.to_f
          b[:rebounds] += pgs.rebounds.to_f
          b[:assists] += pgs.assists.to_f
          b[:steals] += pgs.steals.to_f
          b[:blocks] += pgs.blocks.to_f
          b[:turnovers] += pgs.turnovers.to_f
          b[:fgm] += pgs.fgm.to_f
          b[:fga] += pgs.fga.to_f
          b[:thm] += pgs.three_pt_made.to_f
          b[:tha] += pgs.three_pt_attempted.to_f
        end

        now = Time.current
        bucket.each do |(player_id, opp), b|
          n = b[:n]
          next if n.zero?

          nf = n.to_f
          PlayerOpponentSplit.create!(
            player_id: player_id,
            opponent_team: opp,
            season: @season,
            gp: n,
            avg_minutes: (b[:minutes] / nf).round(2),
            avg_points: (b[:points] / nf).round(2),
            avg_rebounds: (b[:rebounds] / nf).round(2),
            avg_assists: (b[:assists] / nf).round(2),
            avg_steals: (b[:steals] / nf).round(2),
            avg_blocks: (b[:blocks] / nf).round(2),
            avg_turnovers: (b[:turnovers] / nf).round(2),
            avg_fgm: (b[:fgm] / nf).round(2),
            avg_fga: (b[:fga] / nf).round(2),
            avg_three_pt_made: (b[:thm] / nf).round(2),
            avg_three_pt_attempted: (b[:tha] / nf).round(2),
            synced_at: now
          )
        end
      end

      nrows = PlayerOpponentSplit.where(season: @season).count
      Rails.logger.info(
        "[PlayerOpponentSplitsRebuild] season=#{@season} pgs_processed=#{processed} split_rows=#{nrows} skipped_no_opp=#{skipped}"
      )
      Result.new(ok: true, rows_upserted: nrows, error: nil, pgs_processed: processed, skipped_no_opp: skipped)
    rescue StandardError => e
      Rails.logger.error("[PlayerOpponentSplitsRebuild] #{e.class}: #{e.message}")
      Result.new(ok: false, rows_upserted: 0, error: e.message, pgs_processed: nil, skipped_no_opp: nil)
    end
  end
end
