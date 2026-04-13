# frozen_string_literal: true

class CreatePlacedAiSuggestions < ActiveRecord::Migration[5.2]
  def change
    create_table :placed_ai_suggestions do |t|
      t.references :user, foreign_key: true, null: false
      t.references :game, foreign_key: true, null: false
      t.string :external_bet_id
      t.string :slip_kind, null: false, default: 'single'
      t.text :description, null: false
      t.jsonb :legs, null: false, default: []
      t.decimal :decimal_odds, precision: 10, scale: 3
      t.decimal :stake_brl, precision: 10, scale: 2
      t.string :result, null: false, default: 'pending'

      t.timestamps
    end

    add_index :placed_ai_suggestions, %i[user_id game_id]
    add_index :placed_ai_suggestions, %i[user_id external_bet_id],
              unique: true,
              where: "(external_bet_id IS NOT NULL AND external_bet_id <> '')"
  end
end
