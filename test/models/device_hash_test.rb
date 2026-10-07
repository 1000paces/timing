require "test_helper"

class DeviceHashTest < ActiveSupport::TestCase
  VECTOR = JSON.parse(Rails.root.join("test/fixtures/files/device_hash_vector.json").read)

  test "canonical JSON sorts keys, has no whitespace and omits nulls" do
    assert_equal '{"b":1,"c":"x"}', DeviceHash.canonical_json({ "b" => 1, "a" => nil, "c" => "x" })
  end

  test "reproduces the shared vector (also checked by the phone app)" do
    assert_equal VECTOR["genesis"], DeviceHash.genesis(VECTOR["device_id"])
    VECTOR["entries"].each do |e|
      assert_equal e["canonical"], DeviceHash.canonical_json(e["entry"])
      assert_equal e["hash"], DeviceHash.digest(e["entry"])
    end
  end

  test "hub-side entries chain from genesis and verify with the canonical rule" do
    device = create_device(event: create_event)
    capture = Capture.record!(device:, at_ms: 1_000, bib: "101")
    fix = BibAssignment.record!(capture:, bib: "102")
    void = CaptureVoid.record!(capture:)
    assert_equal DeviceHash.genesis(device.id), capture.prev_hash
    [capture, fix, void].each { assert_equal DeviceHash.digest(it.wire), it.entry_hash }
    assert_equal [capture.entry_hash, fix.entry_hash], [fix.prev_hash, void.prev_hash]
    assert_equal({ "id" => void.id, "kind" => "capture_void", "device_seq" => 3, "prev_hash" => fix.entry_hash, "capture_id" => capture.id },
                 void.wire)
  end

  test "a void must be for one of the same device's captures" do
    event = create_event
    other = Capture.record!(device: create_device(event:, name: "Other"), at_ms: 1, bib: "1")
    void = CaptureVoid.new(event:, device: create_device(event:), capture: other, device_seq: 1, prev_hash: "x", entry_hash: "y")
    refute void.valid?
    assert_includes void.errors.full_messages, "Capture must belong to the same device"
  end

  test "a device void takes the capture out of laps and results" do
    event = create_event
    race = create_race(event:)
    register(race:, bib: "101")
    Ruling.create!(event:, kind: "set_race_start", payload: { "race_id" => race.id, "at_ms" => 0 })
    device = create_device(event:)
    first = Capture.record!(device:, at_ms: 60_000, bib: "101")
    extra = Capture.record!(device:, at_ms: 90_000, bib: "101")
    later = Capture.record!(device:, at_ms: 120_000, bib: "101")
    CaptureVoid.record!(capture: extra)
    assert_includes CaptureLaps.voided_ids(event), extra.id
    assert_equal [1, 2], [first, later].map { CaptureLaps.new(event).lap(it) }
    assert_equal 2, StandingsService.report(event).output.races.first.rows.first.laps
  end
end
