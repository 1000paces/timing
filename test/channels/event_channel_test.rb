require "test_helper"

class EventChannelTest < ActionCable::Channel::TestCase
  test "streams the event's changes" do
    event = create_event
    stub_connection current_official: create_official
    subscribe event_id: event.id
    assert subscription.confirmed?
    assert_has_stream EventBroadcast.stream(event.id)
  end

  test "rejects unknown events" do
    stub_connection current_official: create_official
    subscribe event_id: "nope"
    assert subscription.rejected?
  end
end
