class CreateAiPredictions < ActiveRecord::Migration[5.2]
  def change
    create_table :ai_predictions do |t|
      t.references :game, foreign_key: true
      t.references :player, foreign_key: true
      t.jsonb :input_data
      t.text :output_text
      t.decimal :confidence_score

      t.timestamps
    end

    add_index :ai_predictions, [:game_id, :player_id]
  end
end
