require "test_helper"

class EventBroadcastTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @event = create_event
    @race = create_race(event: @event)
    @stream = EventBroadcast.stream(@event.id)
  end

  test "new captures, rulings and registrations announce the event changed" do
    assert_broadcasts(@stream, 1) { record_capture(device: create_device(event: @event), seq: 1, at_ms: 1, bib: "1") }
    assert_broadcasts(@stream, 1) { rule(event: @event, kind: "set_lap_count", start_group_id: @race.start_group_id, laps: 3) }
    assert_broadcasts(@stream, 1) { register(race: @race, bib: "7") }
  end

  test "setup edits announce too" do
    assert_broadcasts(@stream, 1) { @race.start_group.update!(name: "10:05") }
    assert_broadcasts(@stream, 1) { @race.update!(start_offset_ms: 30_000) }
  end

  test "message shape" do
    EventBroadcast.changed(@event.id)
    message = JSON.parse(broadcasts(@stream).last)
    assert_equal "changed", message["type"]
    assert_kind_of Integer, message["at_ms"]
  end
end
