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

ActiveRecord::Schema[8.1].define(version: 2026_10_02_000003) do
  create_table "categories", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.json "ability_levels", default: [], null: false
    t.integer "age_min"
    t.integer "age_max"
    t.string "gender", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["event_id"], name: "index_devices_on_event_id"
  end

  create_table "events", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.date "date", null: false
    t.string "venue"
    t.string "timezone", default: "UTC", null: false
    t.string "age_rule", default: "racing_age_dec31", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  create_table "races", id: :string, force: :cascade do |t|
    t.string "event_id", null: false
    t.string "category_id", null: false
    t.string "start_group_id", null: false
    t.integer "start_offset_ms", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_races_on_category_id"
    t.index ["event_id"], name: "index_races_on_event_id"
    t.index ["start_group_id"], name: "index_races_on_start_group_id"
  end

  create_table "registrations", id: :string, force: :cascade do |t|
    t.string "event_id", null: false
    t.string "race_id", null: false
    t.string "rider_id", null: false
    t.string "bib", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "bib"], name: "index_registrations_on_event_id_and_bib", unique: true
    t.index ["event_id"], name: "index_registrations_on_event_id"
    t.index ["race_id"], name: "index_registrations_on_race_id"
    t.index ["rider_id"], name: "index_registrations_on_rider_id"
  end

  create_table "riders", id: :string, force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "gender", null: false
    t.date "birth_date"
    t.string "ability_level"
    t.string "license_number"
    t.string "team"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["license_number"], name: "index_riders_on_license_number", unique: true
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

  create_table "start_groups", id: :string, force: :cascade do |t|
    t.string "event_id", null: false
    t.string "name", null: false
    t.bigint "scheduled_at_ms"
    t.json "finish_rule", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_start_groups_on_event_id"
  end

  add_foreign_key "device_entries", "device_entries", column: "capture_id"
  add_foreign_key "device_entries", "devices"
  add_foreign_key "device_entries", "events"
  add_foreign_key "devices", "events"
  add_foreign_key "pairing_tokens", "events"
  add_foreign_key "races", "categories"
  add_foreign_key "races", "events"
  add_foreign_key "races", "start_groups"
  add_foreign_key "registrations", "events"
  add_foreign_key "registrations", "races"
  add_foreign_key "registrations", "riders"
  add_foreign_key "rulings", "events"
  add_foreign_key "start_groups", "events"
end
