class RegistrationSetup < ActiveRecord::Migration[8.1]
  def change
    change_table :riders, bulk: true do |t|
      t.string :city
      t.string :state
      t.remove :ability_level, type: :string
    end

    change_column_null :registrations, :bib, true
    change_table :registrations, bulk: true do |t|
      t.integer :age
      t.string :source, null: false, default: "manual"
      t.string :external_category
      t.bigint :checked_in_at_ms
    end

    %i[races events].each do |table|
      change_table table, bulk: true do |t|
        t.integer :bib_from
        t.integer :bib_to
      end
    end

    create_table :category_mappings, id: :string do |t|
      t.references :event, null: false, type: :string, foreign_key: true
      t.string :external_category, null: false
      t.references :race, type: :string, foreign_key: true
      t.boolean :skip, null: false, default: false
      t.timestamps
    end
    add_index :category_mappings, %i[event_id external_category], unique: true
  end
end
