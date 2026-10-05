class Capture < DeviceEntry
  SOURCES = %w[manual chip].freeze

  has_many :bib_assignments, foreign_key: :capture_id, inverse_of: :capture, dependent: :restrict_with_error

  attribute :source, :string, default: "manual"

  validates :captured_at_ms, presence: true
  validates :source, inclusion: { in: SOURCES }

  # Appends a crossing to a hub-side device's log (the console, the simulator):
  # the hub numbers the entry and continues the device's hash chain itself.
  def self.record!(device:, at_ms:, bib:)
    device.with_lock do
      last = DeviceEntry.where(device:).order(:device_seq).last
      prev = last&.entry_hash || Digest::SHA256.hexdigest(device.id)
      id = SecureRandom.uuid_v7(extra_timestamp_bits: 12)
      bib = bib.to_s.strip.presence
      create!(id:, event: device.event, device:, device_seq: (last&.device_seq || 0) + 1, captured_at_ms: at_ms,
              clock_offset_ms: 0, bib:, prev_hash: prev, entry_hash: Digest::SHA256.hexdigest("#{prev}|#{id}|#{at_ms}|#{bib}"))
    end
  end
end
