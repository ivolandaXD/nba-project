# frozen_string_literal: true

module Web
  class PlacedAiSuggestionsController < Web::ApplicationController
    def index
      authorize PlacedAiSuggestion

      @filter = sanitize_filter(params[:filter])
      base =
        current_user.placed_ai_suggestions
                      .includes(:game, placed_ai_suggestion_legs: :player)
                      .order(created_at: :desc)

      @placed_ai_suggestions =
        case @filter
        when 'settled' then base.where.not(result: 'pending')
        when 'pending' then base.where(result: 'pending')
        else base
        end
    end

    def update
      @suggestion = current_user.placed_ai_suggestions.find(params[:id])
      authorize @suggestion

      @suggestion.assign_attributes(update_params)
      if @suggestion.save
        flash[:notice] = 'Sugestão atualizada.'
      else
        flash[:alert] = @suggestion.errors.full_messages.to_sentence
      end

      redirect_back(fallback_location: fallback_after_update(@suggestion), allow_other_host: false)
    end

    def ai_post_mortem
      @suggestion = current_user.placed_ai_suggestions.find(params[:id])
      authorize @suggestion, :ai_post_mortem?

      note = params.dig(:placed_ai_suggestion, :evaluation_note).presence || params[:evaluation_note].presence
      result = Ai::PlacedBetPostMortem.call(placed: @suggestion, evaluation_note: note)

      if result[:ok]
        flash[:notice] = 'Revisão com IA gerada. Role até “Revisão pós-jogo (IA)” abaixo.'
      else
        flash[:alert] = result[:error].presence || 'Falha ao gerar revisão.'
      end

      redirect_back(fallback_location: fallback_after_update(@suggestion), allow_other_host: false)
    end

    private

    def update_params
      params.require(:placed_ai_suggestion).permit(:result, :evaluation_note)
    end

    def fallback_after_update(suggestion)
      g = suggestion.game
      return game_path(g) if g

      placed_ai_suggestions_path
    end

    def sanitize_filter(raw)
      v = raw.to_s.strip
      return 'all' unless %w[all settled pending].include?(v)

      v
    end
  end
end
