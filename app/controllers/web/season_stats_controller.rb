module Web
  class SeasonStatsController < Web::ApplicationController
    def index
      authorize :season_stats, :index?

      @season = Nba::Season.current
      @q = params[:q].to_s.strip
      @sort = sanitize_season_stats_sort(params[:sort])
      @dir = params[:dir] == 'desc' ? 'desc' : 'asc'
      @per_page = season_stats_per_page
      @stats_page = season_stats_current_page

      stats_scope = PlayerSeasonStat.joins(:player).where(season: @season).includes(:player)
      stats_scope = filter_season_stats_by_query(stats_scope, @q)
      stats_scope = stats_scope.order(Arel.sql(season_stats_order_clause(@sort, @dir)))

      @stats_total = stats_scope.count
      @stats_total_pages = [@stats_total.zero? ? 1 : (@stats_total.to_f / @per_page).ceil, 1].max
      @stats_page = [@stats_page, @stats_total_pages].min
      @stats = stats_scope.limit(@per_page).offset((@stats_page - 1) * @per_page)
      synced_ids_scope = PlayerSeasonStat.where(season: @season).select(:player_id)
      @players_without_sync = Player.where.not(nba_player_id: nil)
                                    .where.not(id: synced_ids_scope)
                                    .order(:name)
      @sync_limit = ENV.fetch('NBA_SEASON_SYNC_BATCH', 25).to_i
      @nba_players_count = Player.where.not(nba_player_id: nil).count
    end

    def predict
      authorize :season_stats, :predict?

      safe = PlayerProps::ManualContext.permit_params(
        params,
        :game_id, :player_id, :line, :bet_type, :odds, :user_note
      )
      game = Game.find(safe.require(:game_id))
      authorize game, :show?

      player = Player.find(safe.require(:player_id))
      note = safe[:user_note].to_s.strip
      note = note[0, 2000] if note.length > 2000

      result = Ai::GamePlayerAnalysis.call(
        game: game,
        player: player,
        line: safe[:line].presence,
        bet_type: safe[:bet_type].presence || 'points',
        odds: safe[:odds].presence,
        user_note: note.presence,
        params: safe
      )

      if result[:ok]
        redirect_to ai_hub_path(game_id: game.id),
                    notice: 'Previsão da IA registrada. Veja na Central de IA.'
      else
        redirect_to season_stats_path, alert: result[:error].presence || 'Não foi possível gerar a previsão.'
      end
    end

    def sync
      authorize :season_stats, :sync?

      if truthy?(params[:all])
        PlayerSeasonStatsSyncJob.perform_later
        flash[:notice] =
          'Sincronização de todos os jogadores com NBA ID foi iniciada em segundo plano. ' \
          'Aguarde alguns minutos e atualize a página.'
        redirect_to season_stats_path(season_stats_redirect_params)
        return
      end

      limit = params[:limit].presence&.to_i || ENV.fetch('NBA_SEASON_SYNC_BATCH', 25).to_i
      limit = 1 if limit < 1

      result = NbaStats::PlayerSeasonStatsSync.call(limit: limit)
      if result.success?
        msg = "#{result.synced_count} jogador(es) com estatísticas de temporada atualizadas."
        msg += " Avisos: #{result.errors.join(' | ')}" if result.errors.any?
        flash[:notice] = msg
      else
        flash[:alert] = result.errors.join(' | ').presence || 'Falha ao sincronizar (NBA).'
      end
      redirect_to season_stats_path(season_stats_redirect_params)
    end

    private

    SEASON_STATS_SORTABLE = {
      'player' => 'players.name',
      'team' => 'COALESCE(player_season_stats.team_abbr, players.team)',
      'gp' => 'player_season_stats.gp',
      'min' => 'player_season_stats.min',
      'pts' => 'player_season_stats.pts',
      'reb' => 'player_season_stats.reb',
      'ast' => 'player_season_stats.ast',
      'stl' => 'player_season_stats.stl',
      'blk' => 'player_season_stats.blk',
      'tov' => 'player_season_stats.tov',
      'fgm' => 'player_season_stats.fgm',
      'fga' => 'player_season_stats.fga',
      'fg3m' => 'player_season_stats.fg3m',
      'fg3a' => 'player_season_stats.fg3a',
      'fg_pct' => 'player_season_stats.fg_pct',
      'fg3_pct' => 'player_season_stats.fg3_pct',
      'ft_pct' => 'player_season_stats.ft_pct',
      'synced_at' => 'player_season_stats.synced_at'
    }.freeze

    SEASON_STATS_PER_MIN = 10
    SEASON_STATS_PER_MAX = 20

    def season_stats_per_page
      p = params[:per].presence&.to_i
      p = 15 if p.nil? || p < SEASON_STATS_PER_MIN || p > SEASON_STATS_PER_MAX
      p
    end

    def season_stats_current_page
      p = params[:page].presence&.to_i || 1
      p < 1 ? 1 : p
    end

    def season_stats_redirect_params
      {
        page: params[:page],
        per: params[:per],
        q: params[:q],
        sort: params[:sort],
        dir: params[:dir]
      }
    end

    def sanitize_season_stats_sort(raw)
      s = raw.to_s.presence
      return 'player' unless SEASON_STATS_SORTABLE.key?(s)

      s
    end

    def filter_season_stats_by_query(scope, q)
      return scope if q.blank?

      like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      scope.where(
        'players.name ILIKE ? OR player_season_stats.team_abbr ILIKE ? OR players.team ILIKE ?',
        like,
        like,
        like
      )
    end

    def season_stats_order_clause(sort, dir)
      col = SEASON_STATS_SORTABLE[sort]
      d = dir == 'asc' ? 'ASC' : 'DESC'
      "#{col} #{d} NULLS LAST, players.name ASC, player_season_stats.id ASC"
    end

    def truthy?(v)
      v.present? && v.to_s !~ /\A0|false\z/i
    end
  end
end
