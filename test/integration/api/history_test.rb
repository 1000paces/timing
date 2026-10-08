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

  RACER_FIXES = 'query($id: ID!, $bib: String!) { racer(eventId: $id, bib: $bib) { rulings { description undone } } }'

  test "a crossing's bib is the one a phone or a move gave it, for the description, search and the racer's fixes" do
    tablet = create_device(event: @event)
    loose = record_capture(device: tablet, seq: 1, at_ms: 0, id: "loose")
    BibAssignment.create!(event: @event, device: tablet, capture: loose, bib: "101", device_seq: 2, prev_hash: "x", entry_hash: "y")
    void = RulingWriter.write(event: @event, official: @pat, kind: "void_capture", payload: { capture_id: loose.id })
    blank = record_capture(device: tablet, seq: 3, at_ms: 1000, id: "blank")
    move = RulingWriter.write(event: @event, official: @pat, kind: "assign_bib", payload: { capture_id: blank.id, bib: "205" })
    RulingWriter.write(event: @event, official: @pat, kind: "revert", payload: { ruling_id: move.id })

    assert_equal "Void crossing 00:00:00 (bib 101)", RulingDescriber.new(@event).describe(void)
    assert_includes history(search: "101").map { it["description"] }, "Void crossing 00:00:00 (bib 101)"
    assert_equal "205", history(search: "205").find { it["description"].start_with?("Bib no bib") }&.dig("bib")
    assert_includes gql(RACER_FIXES, id: @event.id, bib: "101").dig("data", "racer", "rulings"), { "description" => "Void crossing 00:00:00 (bib 101)", "undone" => false }
    assert_includes gql(RACER_FIXES, id: @event.id, bib: "205").dig("data", "racer", "rulings"), { "description" => "Bib no bib → 205 for crossing 00:00:01", "undone" => true }
  end

  test "history and the racer panel cost the same number of queries however many fixes there are" do
    tablet = create_device(event: @event)
    counts = [3, 12].map do |n|
      n.times do |i|
        c = record_capture(device: tablet, seq: 100 + Ruling.count + i, at_ms: i * 1000, bib: "101")
        RulingWriter.write(event: @event, official: @pat, kind: "void_capture", payload: { capture_id: c.id })
      end
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        history(search: "101")
        gql(RACER_FIXES, id: @event.id, bib: "101")
      end
      queries
    end
    assert_equal counts.first, counts.last
  end
end
