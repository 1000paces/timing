require "test_helper"

class StartRacesTest < ActionDispatch::IntegrationTest
  START = "mutation($ids: [ID!]!) { startRaces(raceIds: $ids) { rulings { payload } errors } }"
  UNSTART = "mutation($id: ID!) { unstartRace(raceId: $id) { ruling { kind payload } errors } }"
  STARTS = "query($id: ID!) { standings(eventId: $id) { races { race { id } state startAtMs } } }"

  setup do
    StandingsService::LAST_GOOD.clear
    sign_in(create_official(role: "chief", pin: "2468"), "2468")
    @event = create_event
    @a = create_race(event: @event)
    @b = create_race(event: @event, category: nil, gender: "women", name_override: "Women Open")
    @c = create_race(event: @event, category: "Juniors")
  end

  def start_at(race) = gql(STARTS, id: @event.id).dig("data", "standings", "races").find { it.dig("race", "id") == race.id }["startAtMs"]

  test "starting several races gives them one shared hub start time" do
    before = Clock.now_ms
    result = gql(START, ids: [@a.id, @b.id]).dig("data", "startRaces")
    assert_empty result["errors"]
    times = result["rulings"].map { it.dig("payload", "at_ms") }
    assert_equal 2, times.size
    assert_equal 1, times.uniq.size
    assert_operator times.first, :>=, before
    assert_equal times.first, start_at(@a)
    assert_equal times.first, start_at(@b)
    assert_nil start_at(@c)
  end

  test "an already-started race can't be started again, and nothing in that request is started" do
    gql(START, ids: [@a.id])
    result = gql(START, ids: [@c.id, @a.id]).dig("data", "startRaces")
    assert_empty result["rulings"]
    assert_equal ["Cat 3 Men has already started"], result["errors"]
    assert_nil start_at(@c)
  end

  test "unstart removes a race's start so it can be started again" do
    gql(START, ids: [@a.id, @b.id])
    result = gql(UNSTART, id: @a.id).dig("data", "unstartRace")
    assert_empty result["errors"]
    assert_equal "revert", result.dig("ruling", "kind")
    assert_nil start_at(@a)
    refute_nil start_at(@b)
    assert_empty gql(START, ids: [@a.id]).dig("data", "startRaces", "errors")
    refute_nil start_at(@a)
  end

  test "unstarting a race that hasn't started is refused" do
    assert_equal ["Cat 3 Men hasn't started"], gql(UNSTART, id: @a.id).dig("data", "unstartRace", "errors")
  end

  test "starting needs at least one race, and the chief role" do
    assert_equal ["Select at least one race"], gql(START, ids: []).dig("data", "startRaces", "errors")
    delete "/session"
    sign_in(create_official(role: "timer", pin: "1111"), "1111")
    assert_equal "Requires the chief role", gql(START, ids: [@a.id])["errors"].first["message"]
  end
end
