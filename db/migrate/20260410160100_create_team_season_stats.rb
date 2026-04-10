class CreateTeamSeasonStats < ActiveRecord::Migration[5.2]
  def change
    create_table :team_season_stats do |t|
      t.string :season, null: false
      t.string :team_abbr, null: false
      t.string :team_name
      t.integer :gp
      t.integer :w
      t.integer :l
      t.decimal :min, precision: 8, scale: 2
      t.decimal :pts, precision: 8, scale: 2
      t.decimal :reb, precision: 8, scale: 2
      t.decimal :ast, precision: 8, scale: 2
      t.decimal :stl, precision: 8, scale: 2
      t.decimal :blk, precision: 8, scale: 2
      t.decimal :tov, precision: 8, scale: 2
      t.decimal :oreb, precision: 8, scale: 2
      t.decimal :dreb, precision: 8, scale: 2
      t.decimal :fgm, precision: 8, scale: 2
      t.decimal :fga, precision: 8, scale: 2
      t.decimal :fg_pct, precision: 6, scale: 3
      t.decimal :fg3m, precision: 8, scale: 2
      t.decimal :fg3a, precision: 8, scale: 2
      t.decimal :fg3_pct, precision: 6, scale: 3
      t.decimal :ftm, precision: 8, scale: 2
      t.decimal :fta, precision: 8, scale: 2
      t.decimal :ft_pct, precision: 6, scale: 3
      t.jsonb :per_game_row, default: {}, null: false
      t.datetime :synced_at

      t.timestamps
    end

    add_index :team_season_stats, %i[season team_abbr], unique: true, name: 'index_team_season_stats_on_season_and_abbr'
    add_index :team_season_stats, :season
  end
end
