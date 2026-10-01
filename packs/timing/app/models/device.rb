class Device < ApplicationRecord
  belongs_to :event
  has_many :device_entries, dependent: :restrict_with_error

  validates :name, :paired_at_ms, :credential_digest, presence: true

  def revoked? = revoked_at_ms.present?
end
