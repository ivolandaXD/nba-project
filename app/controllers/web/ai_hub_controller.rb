# frozen_string_literal: true

module Web
  class AiHubController < Web::ApplicationController
    def index
      authorize AiHub, :index?

      @season = Nba::Season.current
      @q = params[:q].to_s.strip
      @game_id = params[:game_id].presence
      @sort = sanitize_sort(params[:sort])
      @dir = params[:dir] == 'asc' ? 'asc' : 'desc'

      rel = AiPrediction.joins(:player, :game).includes(:player, :game)
      rel = rel.where(game_id: @game_id) if @game_id.present?

      if @q.present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        rel = rel.where(
          'players.name ILIKE ? OR games.home_team ILIKE ? OR games.away_team ILIKE ?',
          like, like, like
        )
      end

      order_sql = order_clause(@sort, @dir)
      rel = rel.order(Arel.sql(order_sql))

      @predictions_total = rel.count
      @predictions = rel.limit(500)

      from_date = Date.current - 10.days
      to_date = Date.current + 21.days
      @games_for_predict = Game.where(game_date: from_date..to_date).order(game_date: :desc, id: :desc).limit(80)

      @analyze_game = Game.find_by(id: @game_id) if @game_id.present?
      @analyze_players =
        if @analyze_game
          GameRoster.new(game: @analyze_game, season: @season).all_players
        else
          []
        end
    end

    def analyze
      authorize AiHub, :analyze?

      @game = Game.find(params.require(:game_id))
      authorize @game, :analyze?

      player = Player.find(params.require(:player_id))
      gr = GameRoster.new(game: @game, season: Nba::Season.current)
      roster_ids = (gr.home_players.pluck(:id) + gr.away_players.pluck(:id)).uniq
      unless roster_ids.include?(player.id)
        flash[:alert] = 'Jogador não está no elenco deste jogo (times do placar × cadastro).'
        redirect_to ai_hub_path(game_id: @game.id, q: params[:q].presence, sort: params[:sort].presence, dir: params[:dir].presence)
        return
      end

      note = params[:user_note].to_s.strip
      note = note[0, 2000] if note.length > 2000

      safe = PlayerProps::ManualContext.permit_params(
        params,
        :player_id, :game_id, :line, :bet_type, :odds, :confidence_score, :user_note
      )

      prop_focus = Array(params[:prop_focus]).map(&:to_s).reject(&:blank?)
      portfolio_mode = params[:portfolio_mode].to_s == '1'

      result = Ai::GamePlayerAnalysis.call(
        game: @game,
        player: player,
        line: safe[:line].presence,
        bet_type: safe[:bet_type].presence || 'points',
        odds: safe[:odds].presence,
        confidence_score: safe[:confidence_score].presence,
        user_note: note.presence,
        prop_focus: prop_focus,
        portfolio_mode: portfolio_mode,
        params: safe
      )

      if result[:ok]
        flash[:notice] = 'Análise IA concluída.'
      else
        flash[:alert] = result[:error]
      end
      redirect_to ai_hub_path(
        game_id: @game.id,
        q: params[:q].presence,
        sort: params[:sort].presence,
        dir: params[:dir].presence
      )
    end

    private

    SORTABLE = {
      'created_at' => 'ai_predictions.created_at',
      'player' => 'players.name',
      'game' => 'games.game_date',
      'home_team' => 'games.home_team',
      'away_team' => 'games.away_team',
      'stat' => "COALESCE(NULLIF(ai_predictions.input_data->>'stat',''), '')",
      'line' => "(NULLIF(ai_predictions.input_data->>'line',''))::numeric",
      'odds' => "COALESCE(ai_predictions.input_data->>'odds','')",
      'score' => 'ai_predictions.confidence_score',
      'recommendation' => "COALESCE(NULLIF(ai_predictions.analysis_meta->>'recommendation',''), '')",
      'output_text' => 'ai_predictions.output_text'
    }.freeze

    def sanitize_sort(raw)
      s = raw.to_s.presence
      return 'created_at' unless SORTABLE.key?(s)

      s
    end

    def order_clause(sort, dir)
      col = SORTABLE[sort]
      d = dir == 'asc' ? 'ASC' : 'DESC'
      secondary = "ai_predictions.created_at #{d == 'ASC' ? 'DESC' : 'ASC'}"
      "#{col} #{d} NULLS LAST, #{secondary}"
    end
  end
end
