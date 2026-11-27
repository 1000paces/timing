# One-time code shown as a QR code and as short text (e.g. "K7Q-4MX"); a phone
# trades it for a device credential. The code is short enough to type (the iPhone
# home-screen app can't open the QR link); one use, 10 minutes, and pairing
# attempts are rate limited, so ~1e9 possibilities can't be guessed in time.
class PairingToken < ApplicationRecord
  TTL_MS = 10 * 60 * 1000
  ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ".freeze # no 0/O, 1/I/L

  # "k7q 4mx", "K7Q-4MX" and "k7q4mx" are the same code.
  def self.normalize(raw) = raw.to_s.upcase.gsub(/[^#{ALPHABET}]/o, "")

  class Invalid < StandardError; end

  belongs_to :event
  belongs_to :checkpoint, optional: true

  def self.issue!(event:, official:, checkpoint_id: nil)
    code = loop do
      candidate = Array.new(6) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join
      break candidate unless exists?(token_digest: Device.digest(candidate))
    end
    record = create!(event:, token_digest: Device.digest(code), expires_at_ms: Clock.now_ms + TTL_MS,
                     created_by_official_id: official.id, checkpoint_id:)
    [ record, "#{code[0, 3]}-#{code[3, 3]}" ]
  end

  def self.redeem!(raw, device_name:)
    transaction do
      token = lock.find_by(token_digest: Device.digest(normalize(raw)))
      raise Invalid, "Unknown pairing code" unless token
      raise Invalid, "This pairing code has already been used" if token.used_at_ms
      raise Invalid, "This pairing code has expired" if token.expires_at_ms < Clock.now_ms
      token.update!(used_at_ms: Clock.now_ms)
      Device.pair!(event: token.event, name: device_name.presence || "Tablet", checkpoint_id: token.checkpoint_id)
    end
  end
end
