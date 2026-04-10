module Web
  class GamesController < Web::ApplicationController
    def show
      @game = Game.find(params[:id])
      authorize @game, :show?

      @players = Player.joins(:player_game_stats)
                       .where(player_game_stats: { game_id: @game.id })
                       .distinct
                       .order(:name)
      @comments = @game.comments.includes(:user).order(created_at: :desc)
      @predictions = @game.ai_predictions.includes(:player).order(created_at: :desc)
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

      players_scope = Player.joins(:player_game_stats)
                            .where(player_game_stats: { game_id: @game.id })
                            .distinct
      if players_scope.empty?
        flash[:alert] = 'Nenhum jogador com estatística neste jogo.'
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

      player = Player.find(params.require(:player_id))
      result = Ai::GamePlayerAnalysis.call(
        game: @game,
        player: player,
        line: params[:line].presence,
        bet_type: params[:bet_type].presence || 'points',
        odds: params[:odds].presence,
        confidence_score: params[:confidence_score].presence
      )

      if result[:ok]
        flash[:notice] = 'Análise IA concluída.'
      else
        flash[:alert] = result[:error]
      end
      redirect_to game_path(@game)
    end
  end
end
