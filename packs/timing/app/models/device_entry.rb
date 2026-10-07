class DeviceEntry < ApplicationRecord
  include BroadcastsEventChange
  include AppendOnly

  belongs_to :event
  belongs_to :device

  before_validation { self.received_at_ms ||= (Time.now.to_r * 1000).to_i }

  validates :device_seq, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :device_id }
  validates :prev_hash, :entry_hash, :received_at_ms, presence: true

  # Appends to a hub-side device's log (the console, the simulator): the hub
  # numbers the entry and continues the device's hash chain itself.
  def self.append!(device:, hash_parts:, **attrs)
    device.with_lock do
      last = DeviceEntry.where(device:).order(:device_seq).last
      prev = last&.entry_hash || Digest::SHA256.hexdigest(device.id)
      id = SecureRandom.uuid_v7(extra_timestamp_bits: 12)
      create!(id:, event: device.event, device:, device_seq: (last&.device_seq || 0) + 1, prev_hash: prev,
              entry_hash: Digest::SHA256.hexdigest([prev, id, *hash_parts].join("|")), **attrs)
    end
  end
end
