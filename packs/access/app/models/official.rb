class Official < ApplicationRecord
  ROLES = %w[timer chief admin].freeze

  has_secure_password :pin

  scope :active, -> { where(active: true) }

  validates :name, presence: true, uniqueness: true
  validates :role, inclusion: { in: ROLES }
  validates :pin, format: { with: /\A\d{4,8}\z/, message: "must be 4 to 8 digits" }, allow_nil: true

  def at_least?(role)
    wanted = ROLES.index(role.to_s) or raise ArgumentError, "unknown role #{role}"
    ROLES.index(self.role) >= wanted
  end
end
