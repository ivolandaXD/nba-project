class CreatePlayerGameStats < ActiveRecord::Migration[5.2]
  def change
    create_table :player_game_stats do |t|
      t.references :player, foreign_key: true
      t.references :game, foreign_key: true
      t.date :game_date
      t.string :opponent_team
      t.boolean :is_home
      t.decimal :minutes
      t.integer :points
      t.integer :assists
      t.integer :rebounds
      t.integer :steals
      t.integer :blocks
      t.integer :turnovers
      t.integer :fgm
      t.integer :fga
      t.decimal :fg_pct
      t.integer :three_pt_made
      t.integer :three_pt_attempted
      t.decimal :three_pt_pct
      t.integer :ftm
      t.integer :fta
      t.decimal :ft_pct

      t.timestamps
    end

    add_index :player_game_stats, [:player_id, :game_id], unique: true
    add_index :player_game_stats, :game_date
  end
end
