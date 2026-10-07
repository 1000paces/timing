require "test_helper"

class DevicePairingTest < ActionDispatch::IntegrationTest
  setup do
    sign_in(create_official(role: "admin", pin: "1111"), "1111")
    @event = create_event
  end

  def pairing_token
    gql("mutation($id: ID!) { createPairingToken(eventId: $id) { token expiresAtMs pairingUrl errors } }", id: @event.id)
      .dig("data", "createPairingToken")
  end

  test "admin issues a pairing code; a tablet redeems it once; admin sees and revokes the device" do
    issued = pairing_token
    assert_equal "http://www.example.com/capture-app/?pair=#{issued['token'].delete('-')}", issued["pairingUrl"]

    delete "/session" # the tablet has no official session
    post "/devices/pair", params: { token: issued["token"], name: "Finish tablet" }.to_json, headers: ApiHelpers::JSON_HEADERS
    assert_response :created
    paired = response.parsed_body
    assert_equal @event.id, paired["event_id"]
    assert Device.authenticate(paired["device_id"], paired["credential"])

    post "/devices/pair", params: { token: issued["token"], name: "Again" }.to_json, headers: ApiHelpers::JSON_HEADERS
    assert_response :unprocessable_content
    assert_equal "This pairing code has already been used", response.parsed_body["error"]

    sign_in(Official.find_by!(role: "admin"), "1111")
    devices = gql("query($id: ID!) { devices(eventId: $id) { id name revokedAtMs entryCount } }", id: @event.id).dig("data", "devices")
    assert_equal [{ "id" => paired["device_id"], "name" => "Finish tablet", "revokedAtMs" => nil, "entryCount" => 0 }], devices
    gql("mutation($id: ID!) { revokeDevice(deviceId: $id) { errors } }", id: paired["device_id"])
    assert_nil Device.authenticate(paired["device_id"], paired["credential"])
  end

  test "pairing, listing and revoking phones need the chief role" do
    delete "/session"
    sign_in(create_official(role: "chief", pin: "2222"), "2222")
    assert pairing_token["token"].present?
    assert_equal [], gql("query($id: ID!) { devices(eventId: $id) { id } }", id: @event.id).dig("data", "devices")
    delete "/session"
    sign_in(create_official(role: "timer", pin: "3333"), "3333")
    body = gql("mutation($id: ID!) { createPairingToken(eventId: $id) { token } }", id: @event.id)
    assert_equal "Requires the chief role", body["errors"].first["message"]
  end

  # Review Focus 4 (guess-flooding the pairing endpoint)
  test "pairing attempts are rate limited by socket peer, not by a client-supplied X-Forwarded-For" do
    10.times do |i|
      post "/devices/pair", params: { token: "bad-#{i}", name: "T" }.to_json,
                            headers: ApiHelpers::JSON_HEADERS.merge("X-Forwarded-For" => "203.0.113.#{i + 1}")
      assert_response :unprocessable_content
    end
    post "/devices/pair", params: { token: "bad-11", name: "T" }.to_json,
                          headers: ApiHelpers::JSON_HEADERS.merge("X-Forwarded-For" => "203.0.113.99")
    assert_response :too_many_requests
  end
end
