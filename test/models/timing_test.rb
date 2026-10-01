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
    assert rule(event: @event, kind: "set_lap_count", start_group_id: "g1", laps: 5).persisted?
    refute Ruling.new(event: @event, kind: "set_lap_count", payload: { "laps" => 5 }).valid?
    refute Ruling.new(event: @event, kind: "teleport", payload: {}).valid?
  end

  test "rulings are append-only and stamp created_at_ms" do
    ruling = rule(event: @event, kind: "dnf", bib: "7")
    assert_operator ruling.created_at_ms, :>, 1_700_000_000_000
    assert_raises(ActiveRecord::ReadOnlyRecord) { ruling.update!(reason: "oops") }
  end

  test "revoked? reflects revoked_at_ms" do
    refute @device.revoked?
    assert Device.new(revoked_at_ms: 1).revoked?
  end
end
