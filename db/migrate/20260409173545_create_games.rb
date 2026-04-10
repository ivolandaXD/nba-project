class CreateGames < ActiveRecord::Migration[5.2]
  def change
    create_table :games do |t|
      t.date :game_date
      t.string :home_team
      t.string :away_team
      t.string :status
      t.string :nba_game_id

      t.timestamps
    end

    add_index :games, :game_date
    add_index :games, :nba_game_id, unique: true, where: 'nba_game_id IS NOT NULL'
  end
end
