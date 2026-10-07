require "test_helper"

class HistoryTest < ActionDispatch::IntegrationTest
  HISTORY = <<~GQL
    query($id: ID!, $search: String, $limit: Int, $offset: Int) {
      rulings(eventId: $id, search: $search, limit: $limit, offset: $offset) { kind description bib officialName undone undoneBy undoneAtMs }
    }
  GQL

  setup do
    @event = create_event
    race = create_race(event: @event)
    register(race:, bib: "101", racer: create_racer(first_name: "Ann", last_name: "Lee"))
    register(race:, bib: "205", racer: create_racer(first_name: "Bo", last_name: "Yu"))
    @pat = create_official(name: "Pat", role: "chief", pin: "1111")
    sign_in(@pat, "1111")
    @dnf = RulingWriter.write(event: @event, official: @pat, kind: "dnf", payload: { bib: "101" })
    RulingWriter.write(event: @event, official: @pat, kind: "pull", payload: { bib: "205", at_ms: 0 })
    RulingWriter.write(event: @event, official: @pat, kind: "revert", payload: { ruling_id: @dnf.id })
  end

  def history(**vars) = gql(HISTORY, id: @event.id, **vars).dig("data", "rulings")

  test "every ruling, newest first, readable, with who undid what" do
    rows = history
    assert_equal ["Undo: DNF bib 101", "Pull bib 205 at 00:00:00", "DNF bib 101"], rows.map { it["description"] }
    dnf = rows.last
    assert_equal({ "kind" => "dnf", "bib" => "101", "officialName" => "Pat", "undone" => true, "undoneBy" => "Pat" }, dnf.except("description", "undoneAtMs"))
    assert dnf["undoneAtMs"].is_a?(Integer)
  end

  test "search by bib or racer name, and page through" do
    assert_equal ["Pull bib 205 at 00:00:00"], history(search: "205").map { it["description"] }
    assert_equal ["Undo: DNF bib 101", "DNF bib 101"], history(search: "ann lee").map { it["description"] }
    assert_equal ["Pull bib 205 at 00:00:00"], history(limit: 1, offset: 1).map { it["description"] }
  end
end
