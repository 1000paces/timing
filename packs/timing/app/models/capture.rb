class Capture < DeviceEntry
  SOURCES = %w[manual chip].freeze

  has_many :bib_assignments, foreign_key: :capture_id, inverse_of: :capture, dependent: :restrict_with_error

  attribute :source, :string, default: "manual"

  validates :captured_at_ms, presence: true
  validates :source, inclusion: { in: SOURCES }

  # Appends a crossing to a hub-side device's log (the console, the simulator), at the device's checkpoint.
  def self.record!(device:, at_ms:, bib:)
    bib = bib.to_s.strip.presence
    append!(device:, captured_at_ms: at_ms, clock_offset_ms: 0, bib:, checkpoint_id: device.checkpoint_id)
  end
end
