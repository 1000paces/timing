require "test_helper"

class CaptureRecordTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @device = create_device(event: @event)
  end

  test "record! numbers entries per device and chains their hashes" do
    first = Capture.record!(device: @device, at_ms: 1_000, bib: "101")
    second = Capture.record!(device: @device, at_ms: 2_000, bib: nil)
    assert_equal [ 1, 2 ], [ first.device_seq, second.device_seq ]
    assert_equal Digest::SHA256.hexdigest(@device.id), first.prev_hash
    assert_equal first.entry_hash, second.prev_hash
    assert_equal [ @event, "101", 1_000, 0 ], [ first.event, first.bib, first.captured_at_ms, first.clock_offset_ms ]
    assert_nil second.bib
  end

  test "a blank bib is stored as no bib" do
    assert_nil Capture.record!(device: @device, at_ms: 1_000, bib: "  ").bib
  end

  test "a later bib entry is appended to the device's log, chained, and becomes the shown bib" do
    capture = Capture.record!(device: @device, at_ms: 1_000, bib: "999")
    entry = BibAssignment.record!(capture:, bib: " 101 ")
    assert_equal [ 2, capture.entry_hash, "101", capture ], [ entry.device_seq, entry.prev_hash, entry.bib, entry.capture ]
    assert_equal "101", CaptureLaps.new(@event).bib(capture)
  end
end
