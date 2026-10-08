require "test_helper"

class TimingTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @device = create_device(event: @event)
  end

  test "captures are read-only once persisted" do
    capture = record_capture(device: @device, seq: 1, at_ms: 1_000, bib: "1")
    assert_raises(ActiveRecord::ReadOnlyRecord) { capture.update!(bib: "2") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { capture.destroy }
  end

  test "device_seq is unique per device across captures and bib assignments" do
    capture = record_capture(device: @device, seq: 1, at_ms: 1_000)
    clash = BibAssignment.new(event: @event, device: @device, device_seq: 1, capture:, bib: "5", prev_hash: "a", entry_hash: "b")
    refute clash.valid?
    other = create_device(event: @event, name: "Tablet 2")
    assert record_capture(device: other, seq: 1, at_ms: 1_000).persisted?
  end

  test "bib assignment must come from the capture's own device" do
    capture = record_capture(device: @device, seq: 1, at_ms: 1_000)
    other = create_device(event: @event, name: "Tablet 2")
    assignment = BibAssignment.new(event: @event, device: other, device_seq: 1, capture:, bib: "5", prev_hash: "a", entry_hash: "b")
    refute assignment.valid?
    assert_includes assignment.errors[:capture], "must belong to the same device"
  end

  test "capture source must be manual or chip; received_at_ms defaults to now" do
    capture = record_capture(device: @device, seq: 1, at_ms: 1_000)
    assert_equal "manual", capture.source
    assert_operator capture.received_at_ms, :>, 1_700_000_000_000
    refute Capture.new(event: @event, device: @device, device_seq: 2, captured_at_ms: 1, source: "gps", prev_hash: "a", entry_hash: "b").valid?
  end

  test "rulings validate kind and required payload keys" do
    assert rule(event: @event, kind: "set_lap_count", race_id: "r1", laps: 5).persisted?
    refute Ruling.new(event: @event, kind: "set_lap_count", payload: { "laps" => 5 }).valid?
    refute Ruling.new(event: @event, kind: "teleport", payload: {}).valid?
  end

  test "rulings reject wrongly typed payload values" do
    invalid = ->(kind, **payload) { Ruling.new(event: @event, kind:, payload: payload.transform_keys(&:to_s)).tap(&:valid?) }
    [
      [ "set_lap_count", { race_id: "r1", laps: "3" } ],
      [ "set_lap_count", { race_id: "r1", laps: 0 } ],
      [ "set_lap_count", { race_id: "r1", laps: -2 } ],
      [ "set_race_start", { race_id: "r1", at_ms: "5" } ],
      [ "set_race_start", { race_id: "r1", at_ms: nil } ],
      [ "set_race_start", { race_id: "", at_ms: 5 } ],
      [ "assign_bib", { capture_id: "c1", bib: "" } ],
      [ "assign_bib", { capture_id: "c1", bib: 5 } ],
      [ "void_capture", { capture_id: 7 } ],
      [ "revert", { ruling_id: " " } ],
      [ "dismiss_suggestion", { suggestion_key: nil } ]
    ].each do |kind, payload|
      assert invalid.(kind, **payload).errors[:payload].any?, "#{kind} #{payload} should be invalid"
    end
    refute invalid.("insert_capture", bib: "1", at_ms: nil).errors.empty?
  end

  test "rulings accept well typed payload values" do
    assert rule(event: @event, kind: "set_lap_count", race_id: "r1", laps: 1).persisted?
    assert rule(event: @event, kind: "set_race_start", race_id: "r1", at_ms: 5).persisted?
    assert rule(event: @event, kind: "assign_bib", capture_id: "c1", bib: "9").persisted?
  end

  test "bib-bearing rulings require a bib registered in the event, except assign_bib" do
    register(race: create_race(event: @event), bib: "1")
    %w[dnf dns dsq].each { |kind| assert rule(event: @event, kind:, bib: "1").persisted? }
    assert rule(event: @event, kind: "pull", bib: "1", at_ms: 5).persisted?
    assert rule(event: @event, kind: "insert_capture", bib: "1", at_ms: 5).persisted?
    assert rule(event: @event, kind: "flag_finish", bib: "1", capture_id: "c1").persisted?
    assert rule(event: @event, kind: "assign_bib", capture_id: "c1", bib: "404").persisted?

    assert_raises(ActiveRecord::RecordInvalid) { rule(event: @event, kind: "pull", bib: "404", at_ms: 5) }
    assert_raises(ActiveRecord::RecordInvalid) { rule(event: @event, kind: "insert_capture", bib: "404", at_ms: 5) }
    assert_raises(ActiveRecord::RecordInvalid) { rule(event: @event, kind: "dnf", bib: "404") }
    other = create_event(name: "Other")
    assert_raises(ActiveRecord::RecordInvalid) { rule(event: other, kind: "dnf", bib: "1") }
  end

  test "rulings are append-only and stamp created_at_ms" do
    register(race: create_race(event: @event), bib: "7")
    ruling = rule(event: @event, kind: "dnf", bib: "7")
    assert_operator ruling.created_at_ms, :>, 1_700_000_000_000
    assert_raises(ActiveRecord::ReadOnlyRecord) { ruling.update!(reason: "oops") }
  end

  test "revoked? reflects revoked_at_ms" do
    refute @device.revoked?
    assert Device.new(revoked_at_ms: 1).revoked?
  end
end
