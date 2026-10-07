require "test_helper"

class DevicesQueryTest < ActionDispatch::IntegrationTest
  test "the device list carries what the Phones panel shows" do
    sign_in(create_official(role: "chief", pin: "1111"), "1111")
    event = create_event
    device, = Device.pair!(event:, name: "Finish phone")
    device.update_columns(last_seen_at_ms: 5_000, last_sync_at_ms: 4_000, clock_offset_ms: -35, sync_stopped_at_ms: 4_500)
    row = gql("query($id: ID!) { devices(eventId: $id) { name lastSeenAtMs lastSyncAtMs clockOffsetMs syncStoppedAtMs revokedAtMs } }",
              id: event.id).dig("data", "devices").first
    assert_equal({ "name" => "Finish phone", "lastSeenAtMs" => 5_000, "lastSyncAtMs" => 4_000, "clockOffsetMs" => -35,
                   "syncStoppedAtMs" => 4_500, "revokedAtMs" => nil }, row)
  end
end
