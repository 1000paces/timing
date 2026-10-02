require "test_helper"

class RecordCaptureTest < ActionDispatch::IntegrationTest
  RECORD = <<~GQL
    mutation($eventId: ID!, $bib: String) { recordCapture(eventId: $eventId, bib: $bib) { capture { id bib capturedAtMs lap } errors } }
  GQL
  RECENT = <<~GQL
    query($id: ID!) { event(id: $id) { myCaptures { bib capturedAtMs } } }
  GQL

  setup do
    @event = create_event
    @timer = create_official(name: "Pat", role: "timer", pin: "1111")
  end

  test "a timer records captures with and without a bib, stamped with hub time" do
    sign_in(@timer, "1111")
    before = Clock.now_ms
    with_bib = gql(RECORD, eventId: @event.id, bib: "101").dig("data", "recordCapture")
    without = gql(RECORD, eventId: @event.id, bib: "").dig("data", "recordCapture")
    assert_equal [], with_bib["errors"]
    assert_equal "101", with_bib.dig("capture", "bib")
    assert_nil without.dig("capture", "bib")
    assert_operator with_bib.dig("capture", "capturedAtMs"), :>=, before
    assert_operator without.dig("capture", "capturedAtMs"), :<=, Clock.now_ms

    device = Device.find_by!(event: @event, name: "Console – Pat")
    assert_equal [1, 2], Capture.where(device:).order(:device_seq).pluck(:device_seq)
  end

  test "myCaptures lists the official's own console captures, newest first" do
    other = create_official(name: "Sam", role: "timer", pin: "2222")
    sign_in(other, "2222")
    gql(RECORD, eventId: @event.id, bib: "999")
    sign_in(@timer, "1111")
    gql(RECORD, eventId: @event.id, bib: "101")
    gql(RECORD, eventId: @event.id, bib: "102")
    assert_equal %w[102 101], gql(RECENT, id: @event.id).dig("data", "event", "myCaptures").map { it["bib"] }
  end

  test "each capture carries its lap in a started race" do
    race = create_race(event: @event)
    register(race:, bib: "101")
    Ruling.create!(event: @event, kind: "set_race_start", payload: { "race_id" => race.id, "at_ms" => 0 })
    sign_in(@timer, "1111")
    laps = 2.times.map { gql(RECORD, eventId: @event.id, bib: "101").dig("data", "recordCapture", "capture", "lap") }
    assert_equal [1, 2], laps
    assert_equal [2, 1], gql("query($id: ID!) { event(id: $id) { myCaptures { lap } } }", id: @event.id).dig("data", "event", "myCaptures").map { it["lap"] }
  end

  test "recording requires sign in" do
    body = gql(RECORD, eventId: @event.id, bib: "101")
    assert_equal "Sign in required", body["errors"].first["message"]
    assert_equal 0, Capture.count
  end
end
