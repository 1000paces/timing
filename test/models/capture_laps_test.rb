require "test_helper"

class CaptureLapsTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @race = create_race(event: @event)
    @other = create_race(event: @event, category: "Cat 4")
    register(race: @race, bib: "101")
    register(race: @other, bib: "401")
    @tablet = create_device(event: @event, name: "Tablet")
    @console = create_device(event: @event, name: "Console")
    Ruling.create!(event: @event, kind: "set_race_start", payload: { "race_id" => @race.id, "at_ms" => 10_000 })
  end

  def lap(capture) = CaptureLaps.new(@event).lap(capture)

  test "the lap is the count of that bib's captures since its race started, from every device" do
    early = Capture.record!(device: @tablet, at_ms: 9_000, bib: "101")
    first = Capture.record!(device: @tablet, at_ms: 70_000, bib: "101")
    second = Capture.record!(device: @console, at_ms: 130_000, bib: "101")
    third = Capture.record!(device: @tablet, at_ms: 190_000, bib: "101")
    laps = CaptureLaps.new(@event)
    assert_equal [nil, 1, 2, 3], [early, first, second, third].map { laps.lap(it) }
  end

  test "no lap for a race that hasn't started, an unknown bib, or no bib" do
    assert_nil lap(Capture.record!(device: @tablet, at_ms: 70_000, bib: "401"))
    assert_nil lap(Capture.record!(device: @tablet, at_ms: 70_000, bib: "999"))
    assert_nil lap(Capture.record!(device: @tablet, at_ms: 70_000, bib: nil))
  end
end
