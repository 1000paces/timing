class Registration < ApplicationRecord
  SOURCES = %w[manual import].freeze

  include BroadcastsEventChange
  belongs_to :event
  belongs_to :race
  belongs_to :rider

  before_validation do
    self.event_id ||= race&.event_id
    self.bib = bib.to_s.strip.presence
  end

  validates :bib, uniqueness: { scope: :event_id }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }
  validates :age, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :race_in_same_event

  # Warnings, not errors: officials may let riders race up.
  def eligibility_warnings = Eligibility.warnings(rider:, race:, event:, age:)

  def checked_in? = checked_in_at_ms.present?

  def check_in!(at_ms:) = update!(checked_in_at_ms: at_ms)

  def undo_check_in! = update!(checked_in_at_ms: nil)

  private

  def race_in_same_event
    errors.add(:race, "must belong to the same event") if race && race.event_id != event_id
  end
end
