# One-time code shown as a QR code; a tablet trades it for a device credential.
class PairingToken < ApplicationRecord
  TTL_MS = 10 * 60 * 1000

  class Invalid < StandardError; end

  belongs_to :event

  def self.issue!(event:, official:)
    raw = SecureRandom.urlsafe_base64(24)
    record = create!(event:, token_digest: Device.digest(raw), expires_at_ms: Clock.now_ms + TTL_MS,
                     created_by_official_id: official.id)
    [record, raw]
  end

  def self.redeem!(raw, device_name:)
    transaction do
      token = lock.find_by(token_digest: Device.digest(raw.to_s))
      raise Invalid, "Unknown pairing code" unless token
      raise Invalid, "This pairing code has already been used" if token.used_at_ms
      raise Invalid, "This pairing code has expired" if token.expires_at_ms < Clock.now_ms
      token.update!(used_at_ms: Clock.now_ms)
      Device.pair!(event: token.event, name: device_name.presence || "Tablet")
    end
  end
end
