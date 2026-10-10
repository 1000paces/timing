# A timing point on a course event's course (an aid station, "Mile 37"),
# passed once, in position order. The finish isn't one: it is always last,
# with its distance and cutoff on the event.
class Checkpoint < ApplicationRecord
  belongs_to :event

  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :event_id }
  validates :distance_km, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
