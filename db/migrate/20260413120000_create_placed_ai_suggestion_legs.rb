# frozen_string_literal: true

class CreatePlacedAiSuggestionLegs < ActiveRecord::Migration[5.2]
  def change
    create_table :placed_ai_suggestion_legs do |t|
      t.references :placed_ai_suggestion, null: false, foreign_key: true
      t.integer :leg_index, null: false
      t.string :sport, null: false, default: 'nba'
      t.string :event_label
      t.references :game, foreign_key: true
      t.references :player, foreign_key: true
      t.string :team_abbr
      t.string :market_type, null: false
      t.string :selection_type
      t.decimal :line_value, precision: 10, scale: 2
      t.decimal :odds_decimal, precision: 12, scale: 4
      t.string :result_status, null: false, default: 'pending'
      t.decimal :actual_value, precision: 12, scale: 3
      t.decimal :delta_vs_line, precision: 12, scale: 3
      t.decimal :model_confidence_score, precision: 8, scale: 3
      t.decimal :estimated_hit_probability, precision: 8, scale: 5
      t.decimal :market_implied_probability, precision: 8, scale: 5
      t.decimal :edge_percent_points, precision: 10, scale: 4
      t.decimal :ev_estimate, precision: 12, scale: 5
      t.decimal :matched_confidence, precision: 6, scale: 4
      t.string :match_method
      t.jsonb :source_payload, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :placed_ai_suggestion_legs,
              %i[placed_ai_suggestion_id leg_index],
              unique: true,
              name: 'index_pasl_on_placed_and_leg_index'
    add_index :placed_ai_suggestion_legs, :result_status
    add_index :placed_ai_suggestion_legs, :match_method
  end
end
