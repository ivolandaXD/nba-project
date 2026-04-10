class AddCompositeIndexToPlayerGameStats < ActiveRecord::Migration[5.2]
  def change
    add_index :player_game_stats, %i[player_id game_date], name: 'index_pgs_on_player_id_and_game_date'
  end
end
