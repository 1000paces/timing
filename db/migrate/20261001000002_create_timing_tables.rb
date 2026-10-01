class CreateTimingTables < ActiveRecord::Migration[8.1]
  def change
    create_table :devices, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.string :name, null: false
      t.bigint :paired_at_ms, null: false
      t.bigint :revoked_at_ms
      t.string :credential_digest, null: false
      t.timestamps
    end

    # One table for the whole device log: captures and bib assignments share device_seq.
    create_table :device_entries, id: :string do |t|
      t.string :type, null: false
      t.references :event, type: :string, null: false, foreign_key: true
      t.references :device, type: :string, null: false, foreign_key: true
      t.bigint :device_seq, null: false
      t.bigint :captured_at_ms
      t.bigint :clock_offset_ms
      t.string :bib
      t.string :source
      t.references :capture, type: :string, foreign_key: { to_table: :device_entries }
      t.string :prev_hash, null: false
      t.string :entry_hash, null: false
      t.bigint :received_at_ms, null: false
    end
    add_index :device_entries, [:device_id, :device_seq], unique: true

    create_table :rulings, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.string :kind, null: false
      t.json :payload, null: false, default: {}
      t.string :official_id
      t.string :reason
      t.bigint :created_at_ms, null: false
    end
    add_index :rulings, [:event_id, :created_at_ms]
  end
end
