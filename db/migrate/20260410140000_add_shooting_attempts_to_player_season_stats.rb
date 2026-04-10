class AddShootingAttemptsToPlayerSeasonStats < ActiveRecord::Migration[5.2]
  def change
    add_column :player_season_stats, :fgm, :decimal, precision: 8, scale: 2
    add_column :player_season_stats, :fga, :decimal, precision: 8, scale: 2
    add_column :player_season_stats, :fg3m, :decimal, precision: 8, scale: 2
    add_column :player_season_stats, :fg3a, :decimal, precision: 8, scale: 2
  end
end
