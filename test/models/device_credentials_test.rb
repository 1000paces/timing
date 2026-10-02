require "test_helper"

class DeviceCredentialsTest < ActiveSupport::TestCase
  setup { @event = create_event }

  test "pair! issues a credential stored only as a digest" do
    device, credential = Device.pair!(event: @event, name: "Tablet A")
    assert_equal 43, credential.length
    assert_equal Device.digest(credential), device.credential_digest
    assert_equal device, Device.authenticate(device.id, credential)
    assert_nil Device.authenticate(device.id, "wrong")
    assert_nil Device.authenticate("nope", credential)
  end

  # Review Focus 4 (lost tablet)
  test "a revoked device no longer authenticates" do
    device, credential = Device.pair!(event: @event, name: "Tablet A")
    device.revoke!
    assert_nil Device.authenticate(device.id, credential)
  end
end
