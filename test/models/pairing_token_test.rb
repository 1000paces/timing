require "test_helper"

class PairingTokenTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @official = create_official(role: "admin")
  end

  test "a token pairs one device" do
    _record, raw = PairingToken.issue!(event: @event, official: @official)
    device, credential = PairingToken.redeem!(raw, device_name: "Tablet A")
    assert_equal @event, device.event
    assert_equal device, Device.authenticate(device.id, credential)
  end

  # Review Focus 4 (reused or late QR code)
  test "a used or expired token is refused" do
    _record, raw = PairingToken.issue!(event: @event, official: @official)
    PairingToken.redeem!(raw, device_name: "Tablet A")
    error = assert_raises(PairingToken::Invalid) { PairingToken.redeem!(raw, device_name: "Tablet B") }
    assert_equal "This pairing code has already been used", error.message

    record, late = PairingToken.issue!(event: @event, official: @official)
    record.update!(expires_at_ms: Clock.now_ms - 1)
    assert_equal "This pairing code has expired",
                 assert_raises(PairingToken::Invalid) { PairingToken.redeem!(late, device_name: "Tablet C") }.message
    assert_equal "Unknown pairing code",
                 assert_raises(PairingToken::Invalid) { PairingToken.redeem!("made-up", device_name: "Tablet D") }.message
  end

  test "tokens expire ten minutes after issue and are stored as digests" do
    record, raw = PairingToken.issue!(event: @event, official: @official)
    assert_in_delta Clock.now_ms + 600_000, record.expires_at_ms, 2_000
    refute_equal raw, record.token_digest
  end
end
