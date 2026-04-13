# frozen_string_literal: true

class AllowNullGameOnPlacedAiSuggestions < ActiveRecord::Migration[5.2]
  def change
    change_column_null :placed_ai_suggestions, :game_id, true
  end
end
