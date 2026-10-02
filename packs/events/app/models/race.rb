class Race < ApplicationRecord
  GENDERS = { "men" => "Men", "women" => "Women", "open" => "Open" }.freeze

  include BroadcastsEventChange
  belongs_to :event
  has_many :registrations, dependent: :restrict_with_error

  attribute :gender, :string, default: nil
  attribute :scheduled_at_ms, :integer, default: nil

  before_validation do
    %i[category age_group name_override].each { self[it] = self[it].to_s.strip.presence }
  end

  validates :gender, inclusion: { in: GENDERS.keys }
  validates :scheduled_at_ms, presence: true
  validates :expected_laps, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :expected_duration_ms, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :ages_ordered
  validate :name_unique_in_event

  def default_name = [category, age_group, GENDERS[gender]].compact.join(" ")
  def name = name_override || default_name

  def effective_finish_with_leader = finish_with_leader.nil? ? event.finish_with_leader : finish_with_leader

  # The races that finish together with this one: finish-with-leader races at
  # the same scheduled start; otherwise just this race.
  def cohort
    return [self] unless effective_finish_with_leader
    event.races.select { it.scheduled_at_ms == scheduled_at_ms && it.effective_finish_with_leader }
  end

  private

  def ages_ordered
    errors.add(:age_max, "must be greater than or equal to the minimum age") if age_min && age_max && age_max < age_min
  end

  def name_unique_in_event
    return unless event
    taken = event.races.where.not(id:).any? { it.name.casecmp?(name) }
    errors.add(:name, "#{name} is already used in this event") if taken
  end
end
