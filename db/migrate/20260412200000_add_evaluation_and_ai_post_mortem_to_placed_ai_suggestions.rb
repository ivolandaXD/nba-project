# frozen_string_literal: true

class AddEvaluationAndAiPostMortemToPlacedAiSuggestions < ActiveRecord::Migration[5.2]
  def change
    add_column :placed_ai_suggestions, :evaluation_note, :text
    add_column :placed_ai_suggestions, :ai_post_mortem, :text
    add_column :placed_ai_suggestions, :ai_post_mortem_at, :datetime
  end
end
