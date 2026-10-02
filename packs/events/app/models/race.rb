class Race < ApplicationRecord
  include BroadcastsEventChange
  belongs_to :event
  belongs_to :category
  belongs_to :start_group
  has_many :registrations, dependent: :restrict_with_error

  validates :start_offset_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :start_group_in_same_event

  delegate :name, to: :category

  private

  def start_group_in_same_event
    errors.add(:start_group, "must belong to the same event") if start_group && start_group.event_id != event_id
  end
end
