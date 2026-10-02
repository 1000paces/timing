class CreateOfficials < ActiveRecord::Migration[8.1]
  def change
    create_table :officials, id: :string do |t|
      t.string :name, null: false
      t.string :role, null: false
      t.string :pin_digest, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :officials, :name, unique: true
  end
end
