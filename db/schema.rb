# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_06_000004) do
  create_table "category_mappings", id: :string, force: :cascade do |t|
    t.string "event_id", null: false
    t.string "external_category", null: false
    t.string "race_id"
    t.boolean "skip", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "external_category"], name: "index_category_mappings_on_event_id_and_external_category", unique: true
    t.index ["event_id"], name: "index_category_mappings_on_event_id"
    t.index ["race_id"], name: "index_category_mappings_on_race_id"
  end

  create_table "device_entries", id: :string, force: :cascade do |t|
    t.string "type", null: false
    t.string "event_id", null: false
    t.string "device_id", null: false
    t.bigint "device_seq", null: false
    t.bigint "captured_at_ms"
    t.bigint "clock_offset_ms"
    t.string "bib"
    t.string "source"
    t.string "capture_id"
    t.string "prev_hash", null: false
    t.string "entry_hash", null: false
    t.bigint "received_at_ms", null: false
    t.index ["capture_id"], name: "index_device_entries_on_capture_id"
    t.index ["device_id", "device_seq"], name: "index_device_entries_on_device_id_and_device_seq", unique: true
    t.index ["device_id"], name: "index_device_entries_on_device_id"
    t.index ["event_id"], name: "index_device_entries_on_event_id"
  end

  create_table "devices", id: :string, force: :cascade do |t|
    t.string "event_id", null: false
    t.string "name", null: false
    t.bigint "paired_at_ms", null: false
    t.bigint "revoked_at_ms"
    t.string "credential_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "last_seen_at_ms"
    t.bigint "last_sync_at_ms"
    t.bigint "clock_offset_ms"
    t.bigint "sync_stopped_at_ms"
    t.index ["event_id"], name: "index_devices_on_event_id"
  end

  create_table "events", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.date "date", null: false
    t.string "location"
    t.string "timezone", default: "UTC", null: false
    t.string "age_rule", default: "racing_age_dec31", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discipline", default: "cyclocross", null: false
    t.string "sub_discipline"
    t.boolean "finish_with_leader", default: true, null: false
    t.integer "bib_from"
    t.integer "bib_to"
    t.boolean "age_next_year", default: false, null: false
  end

  create_table "officials", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.string "role", null: false
    t.string "pin_digest", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_officials_on_name", unique: true
  end

  create_table "pairing_tokens", id: :string, force: :cascade do |t|
    t.string "event_id", null: false
    t.string "token_digest", null: false
    t.bigint "expires_at_ms", null: false
    t.bigint "used_at_ms"
    t.string "created_by_official_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_pairing_tokens_on_event_id"
    t.index ["token_digest"], name: "index_pairing_tokens_on_token_digest", unique: true
  end

  create_table "racers", id: :string, force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "gender", null: false
    t.date "birth_date"
    t.string "license_number"
    t.string "team"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "city"
    t.string "state"
    t.index ["license_number"], name: "index_racers_on_license_number", unique: true
  end

  create_table "races", id: :string, force: :cascade do |t|
    t.string "event_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category"
    t.string "age_group"
    t.integer "age_min"
    t.integer "age_max"
    t.string "gender", default: "open", null: false
    t.string "name_override"
    t.bigint "scheduled_at_ms", default: 0, null: false
    t.bigint "expected_duration_ms"
    t.integer "expected_laps"
    t.boolean "finish_with_leader"
    t.integer "bib_from"
    t.integer "bib_to"
    t.index ["event_id"], name: "index_races_on_event_id"
  end

  create_table "registrations", id: :string, force: :cascade do |t|
    t.string "event_id", null: false
    t.string "race_id", null: false
    t.string "racer_id", null: false
    t.string "bib"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "age"
    t.string "source", default: "manual", null: false
    t.string "external_category"
    t.bigint "checked_in_at_ms"
    t.index ["event_id", "bib"], name: "index_registrations_on_event_id_and_bib", unique: true
    t.index ["event_id"], name: "index_registrations_on_event_id"
    t.index ["race_id"], name: "index_registrations_on_race_id"
    t.index ["racer_id"], name: "index_registrations_on_racer_id"
  end

  create_table "rulings", id: :string, force: :cascade do |t|
    t.string "event_id", null: false
    t.string "kind", null: false
    t.json "payload", default: {}, null: false
    t.string "official_id"
    t.string "reason"
    t.bigint "created_at_ms", null: false
    t.index ["event_id", "created_at_ms"], name: "index_rulings_on_event_id_and_created_at_ms"
    t.index ["event_id"], name: "index_rulings_on_event_id"
  end

  add_foreign_key "category_mappings", "events"
  add_foreign_key "category_mappings", "races"
  add_foreign_key "device_entries", "device_entries", column: "capture_id"
  add_foreign_key "device_entries", "devices"
  add_foreign_key "device_entries", "events"
  add_foreign_key "devices", "events"
  add_foreign_key "pairing_tokens", "events"
  add_foreign_key "races", "events"
  add_foreign_key "registrations", "events"
  add_foreign_key "registrations", "racers"
  add_foreign_key "registrations", "races"
  add_foreign_key "rulings", "events"
end
