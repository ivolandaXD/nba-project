class AddFinalStatValueToBets < ActiveRecord::Migration[5.2]
  def change
    add_column :bets, :final_stat_value, :decimal, precision: 8, scale: 2
  end
end
