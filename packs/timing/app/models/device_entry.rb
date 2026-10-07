class DeviceEntry < ApplicationRecord
  include BroadcastsEventChange
  include AppendOnly

  belongs_to :event
  belongs_to :device

  before_validation { self.received_at_ms ||= (Time.now.to_r * 1000).to_i }

  validates :device_seq, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :device_id }
  validates :prev_hash, :entry_hash, :received_at_ms, presence: true

  KINDS = { "Capture" => "capture", "BibAssignment" => "bib_assignment", "CaptureVoid" => "capture_void" }.freeze

  # Appends to a hub-side device's log (the console, the simulator): the hub
  # numbers the entry and continues the device's hash chain itself, with the
  # same checksum rule as a phone's entries (DeviceHash).
  def self.append!(device:, **attrs)
    device.with_lock do
      last = DeviceEntry.where(device:).order(:device_seq).last
      entry = new(id: SecureRandom.uuid_v7(extra_timestamp_bits: 12), event: device.event, device:,
                  device_seq: (last&.device_seq || 0) + 1, prev_hash: last&.entry_hash || DeviceHash.genesis(device.id), **attrs)
      entry.entry_hash = DeviceHash.digest(entry.wire)
      entry.save!
      entry
    end
  end

  def kind = KINDS.fetch(self.class.name)

  # The entry as a device sends it, without its hash.
  def wire
    { "id" => id, "kind" => kind, "device_seq" => device_seq, "prev_hash" => prev_hash, "captured_at_ms" => captured_at_ms,
      "clock_offset_ms" => clock_offset_ms, "bib" => bib, "capture_id" => capture_id }.compact
  end
end
