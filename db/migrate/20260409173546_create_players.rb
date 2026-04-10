class CreatePlayers < ActiveRecord::Migration[5.2]
  def change
    create_table :players do |t|
      t.string :name
      t.string :team
      t.integer :nba_player_id

      t.timestamps
    end

    add_index :players, :nba_player_id, unique: true, where: 'nba_player_id IS NOT NULL'
  end
end
