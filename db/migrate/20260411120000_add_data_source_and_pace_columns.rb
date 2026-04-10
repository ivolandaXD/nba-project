# frozen_string_literal: true

class AddDataSourceAndPaceColumns < ActiveRecord::Migration[5.2]
  def change
    add_column :player_game_stats, :data_source, :string unless column_exists?(:player_game_stats, :data_source)
    add_column :player_season_stats, :data_source, :string unless column_exists?(:player_season_stats, :data_source)

    unless column_exists?(:players, :bdl_player_id)
      add_column :players, :bdl_player_id, :integer
      add_index :players, :bdl_player_id, unique: true, where: '(bdl_player_id IS NOT NULL)'
    end

    add_column :team_season_stats, :pace, :decimal, precision: 8, scale: 3 unless column_exists?(:team_season_stats, :pace)
  end
end
