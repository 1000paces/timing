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
    assert_equal [ 1, 2 ], Capture.where(device:).order(:device_seq).pluck(:device_seq)
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
    assert_equal [ 1, 2 ], laps
    rows = gql("query($id: ID!) { event(id: $id) { myCaptures { lap lapMs typicalLapMs lapFlag } } }", id: @event.id).dig("data", "event", "myCaptures")
    assert_equal [ 2, 1 ], rows.map { it["lap"] }
    assert rows.all? { it["lapMs"].is_a?(Integer) && it["typicalLapMs"].nil? && it["lapFlag"].nil? }
  end

  DELETE = <<~GQL
    mutation($id: ID!) { deleteCapture(captureId: $id) { errors } }
  GQL

  test "a timer deletes their own capture: it is voided, leaves myCaptures and stops counting" do
    sign_in(@timer, "1111")
    keep = gql(RECORD, eventId: @event.id, bib: "101").dig("data", "recordCapture", "capture", "id")
    mistake = gql(RECORD, eventId: @event.id, bib: "102").dig("data", "recordCapture", "capture", "id")
    assert_equal [], gql(DELETE, id: mistake).dig("data", "deleteCapture", "errors")
    ruling = Ruling.find_by!(kind: "void_capture")
    assert_equal [ mistake, @timer.id ], [ ruling.payload["capture_id"], ruling.official_id ]
    assert_equal [ keep ], gql(RECENT.sub("bib capturedAtMs", "id"), id: @event.id).dig("data", "event", "myCaptures").map { it["id"] }
    assert_equal [ "That capture is already deleted" ], gql(DELETE, id: mistake).dig("data", "deleteCapture", "errors")
  end

  test "an official can't delete another device's capture" do
    tablet = Capture.record!(device: create_device(event: @event), at_ms: 1_000, bib: "101")
    sign_in(@timer, "1111")
    assert_equal [ "You can only delete your own captures" ], gql(DELETE, id: tablet.id).dig("data", "deleteCapture", "errors")
    assert_equal 0, Ruling.count
  end

  test "myCaptures shows the resolved bib once a crossing is fixed, and what was entered" do
    sign_in(@timer, "1111")
    id = gql(RECORD, eventId: @event.id, bib: "").dig("data", "recordCapture", "capture", "id")
    Ruling.create!(event: @event, kind: "assign_bib", payload: { "capture_id" => id, "bib" => "101" })
    row = gql("query($id: ID!) { event(id: $id) { myCaptures { bib enteredBib } } }", id: @event.id).dig("data", "event", "myCaptures").first
    assert_equal({ "bib" => "101", "enteredBib" => nil }, row)
  end

  CORRECT = <<~GQL
    mutation($id: ID!, $bib: String!) { correctCaptureBib(captureId: $id, bib: $bib) { capture { bib enteredBib bibSource } errors } }
  GQL

  test "a timer corrects or adds the bib on their own crossing" do
    sign_in(@timer, "1111")
    id = gql(RECORD, eventId: @event.id, bib: "").dig("data", "recordCapture", "capture", "id")
    data = gql(CORRECT, id:, bib: "101").dig("data", "correctCaptureBib")
    assert_equal({ "bib" => "101", "enteredBib" => nil, "bibSource" => "DEVICE" }, data["capture"])
    assert_equal [ "Enter a bib (delete the crossing to take it back)" ], gql(CORRECT, id:, bib: " ").dig("data", "correctCaptureBib", "errors")
  end

  test "an official's assignment wins and locks the timer's correction; other devices' crossings are refused" do
    sign_in(@timer, "1111")
    id = gql(RECORD, eventId: @event.id, bib: "").dig("data", "recordCapture", "capture", "id")
    Ruling.create!(event: @event, kind: "assign_bib", payload: { "capture_id" => id, "bib" => "102" })
    assert_equal [ "An official assigned bib 102 to this crossing; change it in the review queue" ],
                 gql(CORRECT, id:, bib: "101").dig("data", "correctCaptureBib", "errors")
    tablet = Capture.record!(device: create_device(event: @event), at_ms: 1, bib: "5")
    assert_equal [ "You can only change your own captures" ], gql(CORRECT, id: tablet.id, bib: "6").dig("data", "correctCaptureBib", "errors")
  end

  test "recording requires sign in" do
    body = gql(RECORD, eventId: @event.id, bib: "101")
    assert_equal "Sign in required", body["errors"].first["message"]
    assert_equal 0, Capture.count
  end
end
