class Device < ApplicationRecord
  belongs_to :event
  belongs_to :checkpoint, optional: true
  has_many :device_entries, dependent: :restrict_with_error

  validates :name, :paired_at_ms, :credential_digest, presence: true

  def self.digest(credential) = Digest::SHA256.hexdigest(credential)

  # Returns [device, credential]; only the digest is stored.
  def self.pair!(event:, name:, checkpoint_id: nil)
    credential = SecureRandom.urlsafe_base64(32)
    device = create!(event:, name:, paired_at_ms: Clock.now_ms, credential_digest: digest(credential), checkpoint_id:,
                     checkpoint_set_at_ms: (Clock.now_ms if checkpoint_id))
    [ device, credential ]
  end

  # The phone or an official moved it (null: the finish). The latest move wins,
  # so a phone that was offline can't undo a later move by the chief.
  def move_to!(checkpoint_id, at_ms:)
    return false if checkpoint_set_at_ms && at_ms < checkpoint_set_at_ms
    update_columns(checkpoint_id:, checkpoint_set_at_ms: at_ms)
  end

  def self.authenticate(id, credential)
    device = find_by(id:)
    return nil unless device && !device.revoked? && credential.is_a?(String)
    ActiveSupport::SecurityUtils.secure_compare(device.credential_digest, digest(credential)) ? device : nil
  end

  def revoked? = revoked_at_ms.present?

  def revoke! = update!(revoked_at_ms: Clock.now_ms)
end
