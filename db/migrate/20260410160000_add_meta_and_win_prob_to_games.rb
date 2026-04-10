class AddMetaAndWinProbToGames < ActiveRecord::Migration[5.2]
  def change
    add_column :games, :meta, :jsonb, default: {}, null: false
    add_column :games, :home_win_prob, :decimal, precision: 6, scale: 4
    add_column :games, :away_win_prob, :decimal, precision: 6, scale: 4
    add_index :games, :meta, using: :gin
  end
end
