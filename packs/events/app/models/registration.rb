class Registration < ApplicationRecord
  SOURCES = %w[manual import].freeze

  include BroadcastsEventChange
  belongs_to :event
  belongs_to :race
  belongs_to :racer

  before_validation do
    self.event_id ||= race&.event_id
    self.bib = bib.to_s.strip.presence
  end

  validates :bib, uniqueness: { scope: :event_id }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }
  validates :age, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :race_in_same_event
  validate :bib_locked_once_checked_in

  # Warnings, not errors: officials may let racers race up.
  def eligibility_warnings = Eligibility.warnings(racer:, race:, event:, age:)

  # The age entered or imported for this event, else worked out from the birth date.
  def racing_age = age || event.age_of(racer.birth_date)

  def checked_in? = checked_in_at_ms.present?

  def check_in!(at_ms:) = update!(checked_in_at_ms: at_ms)

  def undo_check_in! = update!(checked_in_at_ms: nil)

  private

  # A checked-in racer has their number on; give a bib to one without, but
  # don't change one already handed out.
  def bib_locked_once_checked_in
    return unless checked_in_at_ms_in_database && bib_in_database && will_save_change_to_bib?
    errors.add(:bib, "can't change once the racer is checked in (undo check-in first)")
  end

  def race_in_same_event
    errors.add(:race, "must belong to the same event") if race && race.event_id != event_id
  end
end
