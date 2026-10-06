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

  # Racers 101–103 lap in about 60 s; flags compare a lap with the race's
  # typical lap: the median of the race's other laps, lap 1 excluded.
  def lap_at(bib, *times) = times.map { Capture.record!(device: @tablet, at_ms: 10_000 + it * 1000, bib:) }

  test "a roughly double lap is a suspected missed lap; other long laps and very short laps are flagged too" do
    register(race: @race, bib: "102")
    register(race: @race, bib: "103")
    lap_at("102", 65, 125, 185)
    lap_at("103", 70, 130, 190)
    normal, missed, long, short = lap_at("101", 60, 120, 240, 340, 355).last(4)
    laps = CaptureLaps.new(@event)
    info = ->(c) { laps.info(c).then { [it.lap, it.lap_ms, it.typical_ms, it.flag] } }
    assert_equal [2, 60_000, 60_000, nil], info.(normal)
    assert_equal [3, 120_000, 60_000, "missed"], info.(missed)
    assert_equal [4, 100_000, 60_000, "long"], info.(long)
    assert_equal [5, 15_000, 60_000, "short"], info.(short)
  end

  test "no flag on lap 1 or before the race has three laps to compare" do
    first, second = lap_at("101", 200, 400)
    laps = CaptureLaps.new(@event)
    assert_equal [1, 200_000, nil, nil], laps.info(first).then { [it.lap, it.lap_ms, it.typical_ms, it.flag] }
    assert_equal [2, 200_000, nil, nil], laps.info(second).then { [it.lap, it.lap_ms, it.typical_ms, it.flag] }
  end

  test "a voided capture doesn't count; reverting the void restores it" do
    first = Capture.record!(device: @tablet, at_ms: 70_000, bib: "101")
    extra = Capture.record!(device: @tablet, at_ms: 71_000, bib: "101")
    later = Capture.record!(device: @tablet, at_ms: 130_000, bib: "101")
    void = Ruling.create!(event: @event, kind: "void_capture", payload: { "capture_id" => extra.id })
    laps = CaptureLaps.new(@event)
    assert_equal [1, nil, 2], [first, extra, later].map { laps.lap(it) }
    assert laps.voided?(extra)
    Ruling.create!(event: @event, kind: "revert", payload: { "ruling_id" => void.id })
    assert_equal 3, CaptureLaps.new(@event).lap(later)
  end
end
