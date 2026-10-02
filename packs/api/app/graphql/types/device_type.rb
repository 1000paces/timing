module Types
  class DeviceType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :paired_at_ms, Millis, null: false
    field :revoked_at_ms, Millis
    field :last_seen_at_ms, Millis, description: "When the hub last received an entry from it"
    field :entry_count, Integer, null: false
    field :clock_offset_ms, Millis, description: "Offset on its latest capture"

    def last_seen_at_ms = object.device_entries.maximum(:received_at_ms)
    def entry_count = object.device_entries.count
    def clock_offset_ms = Capture.where(device: object).order(device_seq: :desc).pick(:clock_offset_ms)
  end
end
