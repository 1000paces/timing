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
    assert_broadcasts(@stream, 1) { @race.update!(category: create_category(name: "Juniors", gender: "M", ability_levels: [])) }
  end

  test "message shape" do
    EventBroadcast.changed(@event.id)
    message = JSON.parse(broadcasts(@stream).last)
    assert_equal "changed", message["type"]
    assert_kind_of Integer, message["at_ms"]
  end

  test "a failing broadcast does not fail the committed write" do
    server = ActionCable.server
    server.define_singleton_method(:broadcast) { |*| raise "cable down" }
    begin
      assert_difference -> { Ruling.count }, 1 do
        rule(event: @event, kind: "set_lap_count", start_group_id: @race.start_group_id, laps: 3)
      end
      assert_nil EventBroadcast.changed(@event.id)
    ensure
      server.singleton_class.send(:remove_method, :broadcast)
    end
  end
end
