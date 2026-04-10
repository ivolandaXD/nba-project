class CreatePlayerOpponentSplits < ActiveRecord::Migration[5.2]
  def change
    create_table :player_opponent_splits do |t|
      t.references :player, foreign_key: true, null: false
      t.string :opponent_team, null: false
      t.string :season, null: false
      t.integer :gp, null: false

      t.decimal :avg_minutes, precision: 8, scale: 2
      t.decimal :avg_points, precision: 8, scale: 2
      t.decimal :avg_rebounds, precision: 8, scale: 2
      t.decimal :avg_assists, precision: 8, scale: 2
      t.decimal :avg_steals, precision: 8, scale: 2
      t.decimal :avg_blocks, precision: 8, scale: 2
      t.decimal :avg_turnovers, precision: 8, scale: 2
      t.decimal :avg_fgm, precision: 8, scale: 2
      t.decimal :avg_fga, precision: 8, scale: 2
      t.decimal :avg_three_pt_made, precision: 8, scale: 2
      t.decimal :avg_three_pt_attempted, precision: 8, scale: 2

      t.datetime :synced_at

      t.timestamps
    end

    add_index :player_opponent_splits, %i[player_id opponent_team season],
              unique: true,
              name: 'index_player_opp_splits_on_player_opp_season'
    add_index :player_opponent_splits, :season
  end
end
