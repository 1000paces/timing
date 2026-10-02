require "test_helper"

class SetupMutationsTest < ActionDispatch::IntegrationTest
  SIX_PM = 1_791_000_000_000
  RACE_FIELDS = "id name defaultName nameOverride category ageGroup ageMin gender scheduledAtMs expectedLaps expectedDurationMs finishWithLeader finishWithLeaderOverride"
  CREATE_RACE = <<~GQL
    mutation($eventId: ID!, $category: String, $ageGroup: String, $gender: String!, $nameOverride: String, $scheduledAtMs: Millis!, $expectedLaps: Int, $finishWithLeader: Boolean) {
      createRace(eventId: $eventId, category: $category, ageGroup: $ageGroup, gender: $gender, nameOverride: $nameOverride,
                 scheduledAtMs: $scheduledAtMs, expectedLaps: $expectedLaps, finishWithLeader: $finishWithLeader) {
        race { #{RACE_FIELDS} } errors
      }
    }
  GQL

  setup { sign_in(create_official(role: "admin", pin: "1111"), "1111") }

  def create_race_via_api(event_id, **vars) = gql(CREATE_RACE, eventId: event_id, scheduledAtMs: SIX_PM, gender: "men", **vars).dig("data", "createRace")

  test "admin creates an event; finish with leader defaults from the discipline" do
    cx = gql('mutation { createEvent(name: "Sunday CX", date: "2026-10-18", location: "Park", discipline: "cyclocross") { event { id location discipline finishWithLeader } errors } }')
    assert_equal({ "location" => "Park", "discipline" => "cyclocross", "finishWithLeader" => true }, cx.dig("data", "createEvent", "event").except("id"))
    xco = gql('mutation { createEvent(name: "XC", date: "2026-10-18", discipline: "mountain_bike", subDiscipline: "xco") { event { subDiscipline finishWithLeader } errors } }')
    assert_equal({ "subDiscipline" => "xco", "finishWithLeader" => false }, xco.dig("data", "createEvent", "event"))
  end

  # Review Focus 3
  test "a sub-discipline the discipline doesn't have is refused" do
    body = gql('mutation { createEvent(name: "x", date: "2026-10-18", discipline: "road", subDiscipline: "xcc") { event { id } errors } }')
    assert_equal ["Sub discipline xcc is not part of road"], body.dig("data", "createEvent", "errors")
  end

  test "updateEvent edits details" do
    event = create_event
    body = gql('mutation($id: ID!) { updateEvent(id: $id, name: "Renamed", location: "Hill", finishWithLeader: false) { event { name location finishWithLeader } errors } }', id: event.id)
    assert_equal({ "name" => "Renamed", "location" => "Hill", "finishWithLeader" => false }, body.dig("data", "updateEvent", "event"))
  end

  test "races get default names from category, age group and gender; an override wins" do
    event = create_event
    race = create_race_via_api(event.id, category: "Cat 3", ageGroup: "Masters 35+")["race"]
    assert_equal "Cat 3 Masters 35+ Men", race["name"]
    assert_nil race["nameOverride"]
    assert race["finishWithLeader"]
    assert_nil race["finishWithLeaderOverride"]
    elite = create_race_via_api(event.id, category: "Pro", gender: "women", nameOverride: "Elite Women", finishWithLeader: false)["race"]
    assert_equal ["Elite Women", "Pro Women", false, false], elite.values_at("name", "defaultName", "finishWithLeader", "finishWithLeaderOverride")
  end

  # Review Focus 2
  test "a duplicate race name is refused" do
    event = create_event
    create_race_via_api(event.id, category: "Cat 3")
    assert_equal ["Name cat 3 Men is already used in this event"], create_race_via_api(event.id, category: "cat 3")["errors"]
  end

  test "updateRace changes fields and an explicit null clears them" do
    race = create_race(event: create_event, category: "Cat 3", expected_laps: 5, name_override: "Old name")
    body = gql(<<~GQL, id: race.id)
      mutation($id: ID!) { updateRace(id: $id, ageGroup: "U23", expectedLaps: null, nameOverride: null, finishWithLeader: false) { race { #{RACE_FIELDS} } errors } }
    GQL
    updated = body.dig("data", "updateRace", "race")
    assert_equal ["Cat 3 U23 Men", nil, nil, false], updated.values_at("name", "expectedLaps", "nameOverride", "finishWithLeaderOverride")
  end

  # Review Focus 4
  test "a race with registrations or a start can't be deleted; an empty one can" do
    event = create_event
    empty = create_race(event:, category: "A")
    registered = create_race(event:, category: "B")
    register(race: registered, bib: "1")
    started = create_race(event:, category: "C")
    rule(event:, kind: "set_race_start", race_id: started.id, at_ms: 1)
    delete_race = ->(race) { gql("mutation($id: ID!) { deleteRace(id: $id) { errors } }", id: race.id).dig("data", "deleteRace", "errors") }
    assert_equal ["B Men has registrations and can't be deleted"], delete_race.(registered)
    assert_equal ["C Men has started and can't be deleted"], delete_race.(started)
    assert_empty delete_race.(empty)
    refute Race.exists?(empty.id)
  end

  test "the disciplines query lists sub-disciplines and finish-with-leader defaults" do
    list = gql("{ disciplines { id label finishWithLeader subDisciplines { id label finishWithLeader } } }").dig("data", "disciplines")
    mtb = list.find { it["id"] == "mountain_bike" }
    assert_equal({ "id" => "xcc", "label" => "XCC", "finishWithLeader" => true }, mtb["subDisciplines"].find { it["id"] == "xcc" })
    assert(list.find { it["id"] == "cyclocross" }["finishWithLeader"])
  end

  test "setup requires the admin role" do
    delete "/session"
    sign_in(create_official(role: "chief", pin: "2222"), "2222")
    body = gql('mutation { createEvent(name: "x", date: "2026-10-18", discipline: "cyclocross") { event { id } errors } }')
    assert_equal "Requires the admin role", body["errors"].first["message"]
  end

  test "admin creates officials and lists them" do
    body = gql('mutation { createOfficial(name: "Timer Tom", role: "timer", pin: "4321") { official { name role } errors } }')
    assert_equal({ "name" => "Timer Tom", "role" => "timer" }, body.dig("data", "createOfficial", "official"))
    assert_includes gql("{ officials { name } }").dig("data", "officials").map { it["name"] }, "Timer Tom"
  end
end
