module Web
  class GamesController < Web::ApplicationController
    def show
      @game = Game.find(params[:id])
      authorize @game, :show?

      @season = Nba::Season.current
      roster = GameRoster.new(game: @game, season: @season)
      @home_abbr = roster.home_abbr
      @away_abbr = roster.away_abbr

      @team_stats_home = team_season_row(@home_abbr)
      @team_stats_away = team_season_row(@away_abbr)

      @home_roster = roster.home_players
      @away_roster = roster.away_players

      @pgs_by_player_id = PlayerGameStat.where(game_id: @game.id).includes(:player).index_by(&:player_id)

      roster_ids = (@home_roster.pluck(:id) + @away_roster.pluck(:id)).uniq
      @pss_by_player_id =
        if roster_ids.any?
          PlayerSeasonStat.where(season: @season, player_id: roster_ids).index_by(&:player_id)
        else
          {}
        end

      # Props / métricas: elenco dos dois times (não só quem já tem linha neste jogo).
      @players = roster.all_players

      @comments = @game.comments.includes(:user).order(created_at: :desc)
      @my_bets = current_user.bets.where(game_id: @game.id).includes(:player).order(created_at: :desc)
    end

    def fetch_odds
      @game = Game.find(params[:id])
      authorize @game, :fetch_odds?
      result = Odds::GameOddsImporter.call(@game)
      flash_key = result.success? ? :notice : :alert
      flash[flash_key] = result.success? ? "Odds: #{result.snapshots_count} registro(s)." : result.error
      redirect_to game_path(@game)
    end

    def import_game_logs
      @game = Game.find(params[:id])
      authorize @game, :fetch_odds?

      @season = Nba::Season.current
      gr = GameRoster.new(game: @game, season: @season)
      roster_ids = (gr.home_players.pluck(:id) + gr.away_players.pluck(:id)).uniq
      players_scope = roster_ids.any? ? Player.where(id: roster_ids) : Player.none

      if players_scope.empty?
        flash[:alert] = 'Nenhum jogador no elenco dos times deste jogo (confira abreviações e cadastro).'
        redirect_to game_path(@game)
        return
      end

      import_limit = ENV.fetch('NBA_IMPORT_PLAYER_LIMIT', 3).to_i
      import_limit = 3 if import_limit <= 0

      players = players_scope.where.not(nba_player_id: nil).order(:id).limit(import_limit).to_a
      skipped_no_id = players_scope.where(nba_player_id: nil).count
      total_with_id = players_scope.where.not(nba_player_id: nil).count
      skipped_by_limit = [total_with_id - import_limit, 0].max

      errors = []
      imported = 0
      players.each do |player|
        r = NbaStats::PlayerGameLogImporter.call(player)
        if r.success?
          imported += r.stats_count
        else
          errors << "#{player.name}: #{r.error}"
        end
      end

      skipped = skipped_no_id + skipped_by_limit
      if players.empty? && skipped_no_id.positive?
        flash[:alert] = 'Nenhum jogador com nba_player_id configurado para importar logs.'
      elsif imported.zero? && errors.empty? && skipped.positive?
        flash[:alert] = 'Nenhum jogador importado (limite ou IDs ausentes).'
      elsif errors.empty?
        msg = "Importação concluída (#{imported} linha(s), #{players.size} jogador(es) com NBA ID)."
        msg += " Limite de teste: #{import_limit} jogador(es) (NBA_IMPORT_PLAYER_LIMIT); #{skipped_by_limit} não importado(s)." if skipped_by_limit.positive?
        flash[:notice] = msg
      else
        flash[:alert] = "Importação parcial (#{imported} linha(s), #{players.size} jogador(es)). #{errors.join(' | ')}"
      end
      redirect_to game_path(@game)
    end

    def analyze
      @game = Game.find(params[:id])
      authorize @game, :analyze?

      safe = PlayerProps::ManualContext.permit_params(
        params,
        :player_id, :line, :bet_type, :odds, :confidence_score, :user_note
      )
      player = Player.find(safe.require(:player_id))
      note = safe[:user_note].to_s.strip
      note = note[0, 2000] if note.length > 2000

      result = Ai::GamePlayerAnalysis.call(
        game: @game,
        player: player,
        line: safe[:line].presence,
        bet_type: safe[:bet_type].presence || 'points',
        odds: safe[:odds].presence,
        confidence_score: safe[:confidence_score].presence,
        user_note: note.presence,
        params: safe
      )

      if result[:ok]
        flash[:notice] = 'Análise IA concluída. Veja na Central de IA.'
      else
        flash[:alert] = result[:error]
      end
      redirect_to ai_hub_path(game_id: @game.id)
    end

    private

    def team_season_row(abbr)
      return nil if abbr.blank?

      TeamSeasonStat.find_by(season: @season, team_abbr: abbr)
    end

  end
end
