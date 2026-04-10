class CreatePlayerSeasonStats < ActiveRecord::Migration[5.2]
  def change
    create_table :player_season_stats do |t|
      t.references :player, null: false, foreign_key: true
      t.string :season, null: false
      t.string :team_abbr
      t.integer :gp
      t.decimal :min, precision: 8, scale: 2
      t.decimal :pts, precision: 8, scale: 2
      t.decimal :reb, precision: 8, scale: 2
      t.decimal :ast, precision: 8, scale: 2
      t.decimal :stl, precision: 8, scale: 2
      t.decimal :blk, precision: 8, scale: 2
      t.decimal :tov, precision: 8, scale: 2
      t.decimal :fg_pct, precision: 6, scale: 3
      t.decimal :fg3_pct, precision: 6, scale: 3
      t.decimal :ft_pct, precision: 6, scale: 3
      t.jsonb :per_game_row, default: {}, null: false
      t.datetime :synced_at
      t.timestamps
    end

    add_index :player_season_stats, %i[player_id season], unique: true
    add_index :player_season_stats, :season
  end
end
