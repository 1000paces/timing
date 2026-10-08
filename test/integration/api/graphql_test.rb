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
    create_race(event:, scheduled_at_ms: 1_791_000_000_000, expected_duration_ms: 2_700_000)
    data = gql(<<~GQL, id: event.id).dig("data", "event")
      query($id: ID!) { event(id: $id) { name discipline races { name scheduledAtMs expectedDurationMs } } }
    GQL
    assert_equal "cyclocross", data["discipline"]
    assert_equal [ { "name" => "Cat 3 Men", "scheduledAtMs" => 1_791_000_000_000, "expectedDurationMs" => 2_700_000 } ], data["races"]
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

  test "queries nested deeper than the max depth are rejected" do
    body = gql("{ __schema { types { fields { type { ofType { ofType { ofType { ofType { ofType { ofType { ofType { ofType { name } } } } } } } } } } } } }")
    assert body["errors"].present?
    assert_match(/depth/i, body["errors"].first["message"])
  end

  test "non-object variables are a 400, not a 500" do
    sign_in(create_official(pin: "2468"), "2468")
    post "/graphql", params: { query: "{ me { name } }", variables: [ 1, 2 ] }.to_json, headers: ApiHelpers::JSON_HEADERS
    assert_response :bad_request
    assert_equal "variables must be a JSON object", JSON.parse(response.body)["errors"].first["message"]
    post "/graphql", params: { query: "{ me { name } }", variables: "[1,2]" }.to_json, headers: ApiHelpers::JSON_HEADERS
    assert_response :bad_request
  end
end
