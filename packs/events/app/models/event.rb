class Event < ApplicationRecord
  AGE_RULES = %w[racing_age_dec31 age_on_event_date].freeze

  include BibRange

  has_many :races, dependent: :destroy
  has_many :registrations, dependent: :destroy
  has_many :category_mappings, dependent: :destroy

  attribute :finish_with_leader, :boolean, default: nil
  attribute :age_next_year, :boolean, default: nil

  before_validation do
    self.sub_discipline = sub_discipline.presence
    self.finish_with_leader = Disciplines.default_finish_with_leader(discipline, sub_discipline) if finish_with_leader.nil?
    self.age_next_year = Disciplines.default_age_next_year(discipline) if age_next_year.nil?
  end

  validates :name, :date, presence: true
  validates :age_rule, inclusion: { in: AGE_RULES }
  validate :discipline_known
  validate { errors.add(:timezone, "#{timezone} is not a time zone") unless ActiveSupport::TimeZone[timezone.to_s] }

  # Racing age: as of December 31 of the event's year, or of the following year
  # for a season that crosses the year boundary (age_next_year, e.g. CX).
  def age_of(birth_date)
    return nil unless birth_date
    age = date.year + (age_next_year ? 1 : 0) - birth_date.year
    return age if age_rule == "racing_age_dec31"
    birth_date.advance(years: age) > date ? age - 1 : age
  end

  private

  def other_bib_ranges = races.filter_map { |race| [ race.name, race.own_bib_range ] if race.own_bib_range }

  def discipline_known
    errors.add(:sub_discipline, "#{sub_discipline} is not part of #{discipline}") unless Disciplines.valid?(discipline, sub_discipline)
  end
end
