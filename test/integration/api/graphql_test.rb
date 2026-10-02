require "test_helper"

class GraphqlTest < ActionDispatch::IntegrationTest
  test "queries other than me require sign in" do
    body = gql("{ events { id } }")
    assert_equal "Sign in required", body["errors"].first["message"]
  end

  test "me is null when signed out and the official when signed in" do
    assert_nil gql("{ me { name } }").dig("data", "me")
    official = create_official(name: "Pat", role: "chief", pin: "1357")
    sign_in(official, "1357")
    assert_equal({ "name" => "Pat", "role" => "chief" }, gql("{ me { name role } }").dig("data", "me"))
  end

  test "event query returns setup, with millisecond values as JSON numbers" do
    sign_in(create_official(pin: "2468"), "2468")
    event = create_event
    group = create_start_group(event:, scheduled_at_ms: 1_791_000_000_000)
    create_race(event:, start_group: group, start_offset_ms: 30_000)
    data = gql(<<~GQL, id: event.id).dig("data", "event")
      query($id: ID!) { event(id: $id) { name startGroups { scheduledAtMs finishRule races { name startOffsetMs } } } }
    GQL
    group_data = data["startGroups"].first
    assert_equal 1_791_000_000_000, group_data["scheduledAtMs"]
    assert_equal({ "type" => "fixed_laps", "laps" => 3 }, group_data["finishRule"])
    assert_equal [{ "name" => "Cat 3 Men", "startOffsetMs" => 30_000 }], group_data["races"]
  end

  test "a missing record is a GraphQL error, not a server error" do
    sign_in(create_official(pin: "2468"), "2468")
    body = gql("query($id: ID!) { event(id: $id) { name } }", id: "nope")
    assert_response :ok
    assert_equal "Not found", body["errors"].first["message"]
  end

  test "cross-origin GraphQL requests are refused" do
    post "/graphql", params: { query: "{ me { name } }" }.to_json,
                     headers: ApiHelpers::JSON_HEADERS.merge("Origin" => "http://evil.example")
    assert_response :forbidden
  end
end
