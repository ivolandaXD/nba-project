class CreateOddsSnapshots < ActiveRecord::Migration[5.2]
  def change
    create_table :odds_snapshots do |t|
      t.references :game, foreign_key: true
      t.references :player, foreign_key: true, null: true
      t.string :market_type
      t.decimal :line
      t.string :odds
      t.string :source

      t.timestamps
    end

    add_index :odds_snapshots, [:game_id, :market_type, :source]
  end
end
