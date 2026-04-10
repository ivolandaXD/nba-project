class CreateBets < ActiveRecord::Migration[5.2]
  def change
    create_table :bets do |t|
      t.references :user, foreign_key: true
      t.references :game, foreign_key: true
      t.references :player, foreign_key: true
      t.string :bet_type
      t.decimal :line
      t.string :odds
      t.string :result, null: false, default: 'pending'

      t.timestamps
    end

    add_index :bets, [:user_id, :created_at]
  end
end
