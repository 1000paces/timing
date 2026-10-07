# How an import's category text maps to one of the event's races, or is
# skipped (merchandise and the like). Saved so the next import reuses it.
class CategoryMapping < ApplicationRecord
  belongs_to :event
  belongs_to :race, optional: true

  validates :external_category, presence: true, uniqueness: { scope: :event_id }
  validate :race_or_skip

  private

  def race_or_skip
    errors.add(:base, "Choose a race or skip for #{external_category}") if race.nil? == !skip
  end
end
