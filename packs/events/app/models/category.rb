class Category < ApplicationRecord
  GENDERS = %w[M F X open].freeze

  validates :name, presence: true
  validates :gender, inclusion: { in: GENDERS }
  validate :ability_levels_are_strings
  validate :age_range_ordered

  private

  def ability_levels_are_strings
    errors.add(:ability_levels, "must be a list of strings") unless ability_levels.is_a?(Array) && ability_levels.all?(String)
  end

  def age_range_ordered
    errors.add(:age_max, "must be greater than or equal to age_min") if age_min && age_max && age_max < age_min
  end
end
