class CreateAlerts < ActiveRecord::Migration[5.2]
  def change
    create_table :alerts do |t|
      t.references :user, foreign_key: true
      t.references :player, foreign_key: true
      t.string :condition_type
      t.decimal :threshold
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    add_index :alerts, [:user_id, :is_active]
  end
end
