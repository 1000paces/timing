require "test_helper"

class AllCapturesTest < ActionDispatch::IntegrationTest
  CAPTURES = "query($id: ID!) { event(id: $id) { captures { id bib atMs deviceName mine bibSource } } }"
  CORRECT = "mutation($id: ID!, $bib: String!) { correctCaptureBib(captureId: $id, bib: $bib) { errors } }"
  DELETE = "mutation($id: ID!) { deleteCapture(captureId: $id) { errors } }"

  setup do
    @event = create_event
    race = create_race(event: @event)
    %w[101 102].each { register(race:, bib: it) }
    @phone, = Device.pair!(event: @event, name: "Finish phone")
    @tap = Capture.create!(id: "phone-1", event: @event, device: @phone, device_seq: 1, captured_at_ms: 10_000, clock_offset_ms: 250,
                           bib: "101", prev_hash: "p", entry_hash: "h")
  end

  def sign_in_as(role) = create_official(name: "#{role.capitalize} One", role:, pin: "1111").tap { sign_in(it, "1111") }

  test "the console log lists every device's crossings at hub time, newest first, marking the official's own" do
    sign_in_as("timer")
    mine = gql("mutation($e: ID!) { recordCapture(eventId: $e, bib: \"102\") { capture { id } } }", e: @event.id).dig("data", "recordCapture", "capture", "id")
    rows = gql(CAPTURES, id: @event.id).dig("data", "event", "captures")
    assert_equal [ mine, "phone-1" ], rows.map { it["id"] }
    phone_row = rows.last
    assert_equal({ "bib" => "101", "atMs" => 10_250, "deviceName" => "Finish phone", "mine" => false, "bibSource" => "ENTERED" },
                 phone_row.except("id"))
    assert rows.first["mine"]
  end

  test "a timer can't change another device's crossing" do
    sign_in_as("timer")
    assert_equal [ "You can only change your own captures" ], gql(CORRECT, id: @tap.id, bib: "102").dig("data", "correctCaptureBib", "errors")
    assert_equal [ "You can only delete your own captures" ], gql(DELETE, id: @tap.id).dig("data", "deleteCapture", "errors")
  end

  test "a chief corrects and deletes a phone's crossing as official rulings" do
    chief = sign_in_as("chief")
    assert_equal [], gql(CORRECT, id: @tap.id, bib: "102").dig("data", "correctCaptureBib", "errors")
    ruling = Ruling.find_by!(kind: "assign_bib")
    assert_equal [ { "capture_id" => @tap.id, "bib" => "102" }, chief.id ], [ ruling.payload, ruling.official_id ]
    assert_equal "RULING", gql(CAPTURES, id: @event.id).dig("data", "event", "captures").first["bibSource"]

    assert_equal [], gql(DELETE, id: @tap.id).dig("data", "deleteCapture", "errors")
    assert Ruling.exists?(kind: "void_capture")
    assert_equal [], gql(CAPTURES, id: @event.id).dig("data", "event", "captures")
  end

  test "a chief can change a bib an official already assigned, even on their own crossing" do
    sign_in_as("chief")
    mine = gql("mutation($e: ID!) { recordCapture(eventId: $e, bib: \"\") { capture { id } } }", e: @event.id).dig("data", "recordCapture", "capture", "id")
    Ruling.create!(event: @event, kind: "assign_bib", payload: { "capture_id" => mine, "bib" => "101" })
    assert_equal [], gql(CORRECT, id: mine, bib: "102").dig("data", "correctCaptureBib", "errors")
    assert_equal "102", CaptureLaps.new(@event).bib(Capture.find(mine))
  end
end
