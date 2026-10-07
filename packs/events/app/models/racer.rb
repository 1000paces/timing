class Racer < ApplicationRecord
  GENDERS = %w[M F X].freeze

  has_many :registrations, dependent: :restrict_with_error

  validates :first_name, :last_name, presence: true
  validates :gender, inclusion: { in: GENDERS }
  validates :license_number, uniqueness: true, allow_nil: true

  def full_name = "#{first_name} #{last_name}"
end
