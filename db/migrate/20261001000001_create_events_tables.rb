class CreateEventsTables < ActiveRecord::Migration[8.1]
  def change
    create_table :events, id: :string do |t|
      t.string :name, null: false
      t.date :date, null: false
      t.string :venue
      t.string :timezone, null: false, default: "UTC"
      t.string :age_rule, null: false, default: "racing_age_dec31"
      t.timestamps
    end

    create_table :categories, id: :string do |t|
      t.string :name, null: false
      t.json :ability_levels, null: false, default: []
      t.integer :age_min
      t.integer :age_max
      t.string :gender, null: false
      t.timestamps
    end

    create_table :start_groups, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.string :name, null: false
      t.bigint :scheduled_at_ms
      t.json :finish_rule, null: false
      t.timestamps
    end

    create_table :races, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.references :category, type: :string, null: false, foreign_key: true
      t.references :start_group, type: :string, null: false, foreign_key: true
      t.integer :start_offset_ms, null: false, default: 0
      t.timestamps
    end

    create_table :riders, id: :string do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :gender, null: false
      t.date :birth_date
      t.string :ability_level
      t.string :license_number
      t.string :team
      t.timestamps
    end

    create_table :registrations, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.references :race, type: :string, null: false, foreign_key: true
      t.references :rider, type: :string, null: false, foreign_key: true
      t.string :bib, null: false
      t.timestamps
    end
    add_index :registrations, [:event_id, :bib], unique: true
  end
end
