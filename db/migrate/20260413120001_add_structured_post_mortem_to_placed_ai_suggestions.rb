# frozen_string_literal: true

class AddStructuredPostMortemToPlacedAiSuggestions < ActiveRecord::Migration[5.2]
  def change
    add_column :placed_ai_suggestions, :ai_post_mortem_structured, :jsonb, null: false, default: {}
    add_column :placed_ai_suggestions, :ai_post_mortem_parse_error, :text
  end
end
