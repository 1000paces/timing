# Races carry their own category, age group, gender, schedule and lap
# expectations; start groups and category records go away. There is no
# production data, so this does not carry existing rows across.
class EventRaceSetup < ActiveRecord::Migration[8.1]
  def change
    rename_column :events, :venue, :location
    add_column :events, :discipline, :string, null: false, default: "cyclocross"
    add_column :events, :sub_discipline, :string
    add_column :events, :finish_with_leader, :boolean, null: false, default: true

    remove_reference :races, :start_group, type: :string, foreign_key: true, index: true
    remove_reference :races, :category, type: :string, foreign_key: true, index: true
    change_table :races, bulk: true do |t|
      t.string :category
      t.string :age_group
      t.integer :age_min
      t.integer :age_max
      t.string :gender, null: false, default: "open"
      t.string :name_override
      t.bigint :scheduled_at_ms, null: false, default: 0
      t.bigint :expected_duration_ms
      t.integer :expected_laps
      t.boolean :finish_with_leader
    end

    drop_table :start_groups do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.string :name, null: false
      t.bigint :scheduled_at_ms
      t.json :finish_rule, null: false
      t.timestamps
    end
    drop_table :categories do |t|
      t.string :name, null: false
      t.json :ability_levels, null: false, default: []
      t.integer :age_min
      t.integer :age_max
      t.string :gender, null: false
      t.timestamps
    end
  end
end
