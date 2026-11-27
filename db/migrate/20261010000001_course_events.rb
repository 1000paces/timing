class CourseEvents < ActiveRecord::Migration[8.1]
  def change
    change_table :events, bulk: true do |t|
      t.string :race_format, null: false, default: "laps"
      t.decimal :finish_distance_km, precision: 8, scale: 3
      t.bigint :finish_cutoff_at_ms
    end

    create_table :checkpoints, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :name, null: false
      t.decimal :distance_km, precision: 8, scale: 3
      t.bigint :cutoff_at_ms
      t.index [ :event_id, :position ], unique: true
    end

    add_reference :devices, :checkpoint, type: :string, foreign_key: { on_delete: :nullify }
    add_column :devices, :checkpoint_set_at_ms, :bigint
    add_reference :pairing_tokens, :checkpoint, type: :string, foreign_key: { on_delete: :nullify }
    add_reference :device_entries, :checkpoint, type: :string, foreign_key: true
  end
end
