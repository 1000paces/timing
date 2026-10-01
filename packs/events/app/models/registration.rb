class Registration < ApplicationRecord
  belongs_to :event
  belongs_to :race
  belongs_to :rider

  before_validation do
    self.event_id ||= race&.event_id
    self.bib = bib.to_s.strip.presence
  end

  validates :bib, presence: true, uniqueness: { scope: :event_id }
  validate :race_in_same_event

  # Warnings, not errors: officials may let riders race up a category.
  def eligibility_warnings = Eligibility.warnings(rider:, category: race.category, event:)

  private

  def race_in_same_event
    errors.add(:race, "must belong to the same event") if race && race.event_id != event_id
  end
end
