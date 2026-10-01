class Event < ApplicationRecord
  AGE_RULES = %w[racing_age_dec31 age_on_event_date].freeze

  has_many :start_groups, dependent: :destroy
  has_many :races, dependent: :destroy
  has_many :registrations, dependent: :destroy

  validates :name, :date, presence: true
  validates :age_rule, inclusion: { in: AGE_RULES }

  def age_of(birth_date)
    return nil unless birth_date
    age = date.year - birth_date.year
    return age if age_rule == "racing_age_dec31"
    birth_date.advance(years: age) > date ? age - 1 : age
  end
end
