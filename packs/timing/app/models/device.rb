class Device < ApplicationRecord
  belongs_to :event
  has_many :device_entries, dependent: :restrict_with_error

  validates :name, :paired_at_ms, :credential_digest, presence: true

  def self.digest(credential) = Digest::SHA256.hexdigest(credential)

  # Returns [device, credential]; only the digest is stored.
  def self.pair!(event:, name:)
    credential = SecureRandom.urlsafe_base64(32)
    [create!(event:, name:, paired_at_ms: Clock.now_ms, credential_digest: digest(credential)), credential]
  end

  def self.authenticate(id, credential)
    device = find_by(id:)
    return nil unless device && !device.revoked? && credential.is_a?(String)
    ActiveSupport::SecurityUtils.secure_compare(device.credential_digest, digest(credential)) ? device : nil
  end

  def revoked? = revoked_at_ms.present?

  def revoke! = update!(revoked_at_ms: Clock.now_ms)
end
