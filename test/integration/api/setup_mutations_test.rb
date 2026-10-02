require "test_helper"

class SetupMutationsTest < ActionDispatch::IntegrationTest
  setup do
    admin = create_official(role: "admin", pin: "1111")
    sign_in(admin, "1111")
  end

  test "admin builds an event, start group, race, and registers a rider with warnings" do
    event_id = gql(<<~GQL).dig("data", "createEvent", "event", "id")
      mutation { createEvent(name: "Sunday CX", date: "2026-10-18", venue: "Park") { event { id } errors } }
    GQL
    category_id = gql(<<~GQL).dig("data", "createCategory", "category", "id")
      mutation { createCategory(name: "Masters 50+ Men", gender: "M", abilityLevels: [], ageMin: 50) { category { id } errors } }
    GQL
    group_id = gql(<<~GQL, eventId: event_id).dig("data", "createStartGroup", "startGroup", "id")
      mutation($eventId: ID!) {
        createStartGroup(eventId: $eventId, name: "10:00", finishRule: {type: "timed", target_duration_ms: 2700000}) { startGroup { id } errors }
      }
    GQL
    race_id = gql(<<~GQL, eventId: event_id, categoryId: category_id, groupId: group_id).dig("data", "createRace", "race", "id")
      mutation($eventId: ID!, $categoryId: ID!, $groupId: ID!) {
        createRace(eventId: $eventId, categoryId: $categoryId, startGroupId: $groupId) { race { id name } errors }
      }
    GQL
    result = gql(<<~GQL, raceId: race_id).dig("data", "registerRider")
      mutation($raceId: ID!) {
        registerRider(raceId: $raceId, bib: "201", rider: {firstName: "Bo", lastName: "Yu", gender: "M", birthDate: "1990-01-01"}) {
          registration { bib rider { firstName } } warnings errors
        }
      }
    GQL
    assert_equal({ "bib" => "201", "rider" => { "firstName" => "Bo" } }, result["registration"])
    assert_equal ["age 36 is below minimum 50"], result["warnings"]
    assert_empty result["errors"]

    regs = gql("query($id: ID!) { event(id: $id) { registrations { bib raceId eligibilityWarnings } } }", id: event_id)
    assert_equal [{ "bib" => "201", "raceId" => race_id, "eligibilityWarnings" => ["age 36 is below minimum 50"] }],
                 regs.dig("data", "event", "registrations")
  end

  test "validation problems come back as errors data" do
    event = create_event
    body = gql(<<~GQL, eventId: event.id)
      mutation($eventId: ID!) { createStartGroup(eventId: $eventId, name: "x", finishRule: {type: "sprint"}) { startGroup { id } errors } }
    GQL
    assert_nil body.dig("data", "createStartGroup", "startGroup")
    assert_equal ["Finish rule type must be fixed_laps or timed"], body.dig("data", "createStartGroup", "errors")
  end

  test "update start group changes the finish rule" do
    group = create_start_group(event: create_event)
    body = gql(<<~GQL, id: group.id)
      mutation($id: ID!) { updateStartGroup(id: $id, finishRule: {type: "fixed_laps", laps: 8}) { startGroup { finishRule } errors } }
    GQL
    assert_equal({ "type" => "fixed_laps", "laps" => 8 }, body.dig("data", "updateStartGroup", "startGroup", "finishRule"))
  end

  test "admin creates officials and lists them" do
    body = gql('mutation { createOfficial(name: "Timer Tom", role: "timer", pin: "4321") { official { name role } errors } }')
    assert_equal({ "name" => "Timer Tom", "role" => "timer" }, body.dig("data", "createOfficial", "official"))
    assert_includes gql("{ officials { name } }").dig("data", "officials").map { it["name"] }, "Timer Tom"
  end

  test "setup requires the admin role" do
    delete "/session"
    chief = create_official(role: "chief", pin: "2222")
    sign_in(chief, "2222")
    body = gql('mutation { createEvent(name: "x", date: "2026-10-18") { event { id } errors } }')
    assert_equal "Requires the admin role", body["errors"].first["message"]
  end
end
