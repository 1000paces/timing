require "test_helper"

class RegistrationMutationsTest < ActionDispatch::IntegrationTest
  REG = "id bib age source checkedInAtMs race { id name } rider { firstName city state } eligibilityWarnings"

  setup do
    @event = create_event
    @cat3 = create_race(event: @event, category: "Cat 3", gender: "men", bib_from: 100, bib_to: 199)
    @masters = create_race(event: @event, category: "Masters", gender: "men", age_min: 50)
  end

  def as(role) = sign_in(create_official(role:, pin: "1111"), "1111")
  def data(body, key) = body.dig("data", key)

  def walk_up(race: @cat3, bib: nil, age: nil, first: "Walk")
    gql(<<~GQL, raceId: race.id, bib:, age:, rider: { firstName: first, lastName: "Up", gender: "M", city: "Lyons", state: "CO" })
      mutation($raceId: ID!, $bib: String, $age: Int, $rider: RiderInput!) {
        registerRider(raceId: $raceId, bib: $bib, age: $age, rider: $rider) { registration { #{REG} } warnings errors }
      }
    GQL
  end

  test "a chief adds a walk-up: manual, checked in, bib optional" do
    as("chief")
    reg = data(walk_up, "registerRider")["registration"]
    assert_equal [nil, "manual", "Lyons", "CO"], [reg["bib"], reg["source"], reg.dig("rider", "city"), reg.dig("rider", "state")]
    assert reg["checkedInAtMs"].is_a?(Integer)
  end

  test "a timer can read registrations but not change them" do
    as("timer")
    assert_equal "Requires the chief role", walk_up["errors"].first["message"]
  end

  # Review Focus 4
  test "updateRegistration moves races keeping the bib, recomputes warnings, and refuses a taken bib" do
    as("chief")
    reg = data(walk_up(bib: "150", age: 40), "registerRider")["registration"]
    update = <<~GQL
      mutation($id: ID!, $raceId: ID, $bib: String) { updateRegistration(id: $id, raceId: $raceId, bib: $bib) { registration { #{REG} } warnings errors } }
    GQL
    moved = data(gql(update, id: reg["id"], raceId: @masters.id), "updateRegistration")
    assert_equal ["150", @masters.id], [moved.dig("registration", "bib"), moved.dig("registration", "race", "id")]
    assert_equal ["age 40 is below minimum 50"], moved["warnings"]

    data(walk_up(bib: "151", first: "Other"), "registerRider")
    taken = data(gql(update, id: reg["id"], bib: "151"), "updateRegistration")
    assert_equal ["Bib has already been taken"], taken["errors"]
    cleared = data(gql(update, id: reg["id"], bib: nil), "updateRegistration")
    assert_nil cleared.dig("registration", "bib")
  end

  test "updateRegistration edits rider fields" do
    as("chief")
    reg = data(walk_up, "registerRider")["registration"]
    body = gql(<<~GQL, id: reg["id"], rider: { firstName: "Wally", lastName: "Up", gender: "M", team: "Velo" })
      mutation($id: ID!, $rider: RiderInput) { updateRegistration(id: $id, rider: $rider) { registration { rider { firstName team } } errors } }
    GQL
    assert_equal({ "firstName" => "Wally", "team" => "Velo" }, data(body, "updateRegistration").dig("registration", "rider"))
  end

  test "check in and undo; counts follow" do
    as("chief")
    reg = register(race: @cat3, bib: nil)
    set = "mutation($id: ID!, $c: Boolean!) { setCheckedIn(registrationId: $id, checkedIn: $c) { registration { checkedInAtMs } errors } }"
    assert data(gql(set, id: reg.id, c: true), "setCheckedIn").dig("registration", "checkedInAtMs").is_a?(Integer)
    counts = "query($id: ID!) { event(id: $id) { registrationCounts { registered checkedIn needsBib } } }"
    assert_equal({ "registered" => 1, "checkedIn" => 1, "needsBib" => 1 }, gql(counts, id: @event.id).dig("data", "event", "registrationCounts"))
    assert_nil data(gql(set, id: reg.id, c: false), "setCheckedIn").dig("registration", "checkedInAtMs")
  end

  test "removal is refused once the bib has captures" do
    as("chief")
    captured = register(race: @cat3, bib: "101")
    Capture.record!(device: create_device(event: @event), at_ms: 1, bib: "101")
    spare = register(race: @cat3, bib: "102")
    remove = "mutation($id: ID!) { removeRegistration(id: $id) { errors } }"
    assert_equal ["Bib 101 has captures and can't be removed"], data(gql(remove, id: captured.id), "removeRegistration")["errors"]
    assert_equal [], data(gql(remove, id: spare.id), "removeRegistration")["errors"]
    refute Registration.exists?(spare.id)
  end

  test "assignBibs fills from the range and reports what it couldn't" do
    as("chief")
    register(race: @cat3, bib: nil, rider: create_rider(first_name: "Amy", last_name: "Adams"))
    register(race: @masters, bib: nil)
    body = gql("mutation($id: ID!) { assignBibs(eventId: $id) { assigned { bib name raceName } unfilled errors } }", id: @event.id)
    assert_equal({ "assigned" => [{ "bib" => "100", "name" => "Amy Adams", "raceName" => "Cat 3 Men" }],
                   "unfilled" => ["Masters Men: 1 rider still needs a bib — no bib range"], "errors" => [] }, data(body, "assignBibs"))
  end

  test "bib ranges are set on events and races by admins" do
    as("admin")
    body = gql("mutation($id: ID!) { updateEvent(id: $id, bibFrom: 500, bibTo: 599) { event { bibFrom bibTo } errors } }", id: @event.id)
    assert_equal({ "bibFrom" => 500, "bibTo" => 599 }, data(body, "updateEvent")["event"])
    body = gql("mutation($id: ID!) { updateRace(id: $id, bibFrom: 150, bibTo: 250) { race { bibFrom } errors } }", id: @masters.id)
    assert_equal ["Bib range 150–250 overlaps Cat 3 Men (100–199)"], data(body, "updateRace")["errors"]
  end
end
