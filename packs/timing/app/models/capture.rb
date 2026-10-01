class Capture < DeviceEntry
  SOURCES = %w[manual chip].freeze

  has_many :bib_assignments, foreign_key: :capture_id, inverse_of: :capture, dependent: :restrict_with_error

  attribute :source, :string, default: "manual"

  validates :captured_at_ms, presence: true
  validates :source, inclusion: { in: SOURCES }
end
