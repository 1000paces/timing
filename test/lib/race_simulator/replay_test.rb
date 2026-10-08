require "test_helper"

class RaceSimulator::ReplayTest < ActiveSupport::TestCase
  DATASET = RaceSimulator::Replay::Dataset.load("cascade_locks_1")

  test "the dataset has every racer of the real results, each category in exactly one wave" do
    assert_equal 219, DATASET.results.size
    assert_equal 34, DATASET.races.size
    assert_equal DATASET.results.map(&:category).uniq.sort, DATASET.races.map(&:name).sort
    cat4 = DATASET.results.find { it.bib == "381" }
    assert_equal ["Category 4 Open", 1, 6], [cat4.category, cat4.place, cat4.laps]
    assert_equal [428_960, 445_980], cat4.laps_ms.first(2)
    assert_equal [561_000, 577_000], DATASET.results.find { it.bib == "243" }.laps_ms # the running race is in h:mm:ss
  end

  test "a wave's lap count is the one that best explains who stopped when" do
    # Three racers finish on lap 3 after the leader's 3rd crossing opens the finish; the leader rode on
    # to lap 4. A lap count of 4 would instead have all three stopping early.
    wave = RaceSimulator::Replay::Wave.new(gun: "10:00", minutes: 45, arm_s: 0, races: [])
    racers = [[100, 200, 300, 400], [110, 210, 310], [120, 220, 320], [130, 230, 330]].map { RaceSimulator::Replay::Result.new(category: "x", place: 1, bib: "1", laps: it.size, laps_ms: it.each_cons(2).map { |a, b| b - a }.unshift(it.first)) }
    assert_equal 3, wave.lap_count(racers)
  end

  test "setup builds the real event: races in waves, real bibs, made-up names, Pacific time" do
    event = RaceSimulator::Replay.setup!(DATASET)
    assert_equal ["Cross Crusade Cascade Locks 1", Date.new(2026, 9, 27), "America/Los_Angeles", "cyclocross"], [event.name, event.date, event.timezone, event.discipline]
    assert_equal 34, event.races.count
    assert_equal DATASET.results.map(&:bib).sort, event.registrations.pluck(:bib).sort
    masters = event.races.find_by(name_override: "Masters 50+")
    assert_equal Time.find_zone("America/Los_Angeles").parse("2026-09-27 10:00").to_i * 1000, masters.scheduled_at_ms
    assert_equal 1, event.races.where(scheduled_at_ms: masters.scheduled_at_ms).pluck(:scheduled_at_ms).uniq.size
    assert_equal "Athenas", event.races.find_by(gender: "women", name_override: "Athenas").name
    assert_equal "Cross Crusade Cascade Locks 1 (2)", RaceSimulator::Replay.setup!(DATASET).name
  end

  test "a clean replay matches the real results, apart from the known oddities" do
    event = RaceSimulator::Replay.setup!(DATASET)
    RaceSimulator::Replay.run(event:, dataset: DATASET, speed: 0, out: StringIO.new)
    check = RaceSimulator::Replay::Check.new(event:, dataset: DATASET)
    assert_equal 34, check.races_checked
    assert_equal KNOWN_MISMATCHES, check.mismatches.map(&:to_s).sort
    assert_equal 57, check.stopped_early.size
    assert_equal check.stopped_early.size, check.stopped_early.map(&:bib).uniq.size
  end

  # What the real event did that a finish-with-leader rule doesn't: everything
  # else (places, laps, every lap time) matches the published results.
  KNOWN_MISMATCHES = [
    "Category 3 Masters Open 35+ #43: laps ours 6, theirs 7", # rode a lap past the finish; the timing system counted it
    "Junior Open 13-14 #70: laps ours 3, theirs 4",           # a 6:49 last lap after a 10:46: rode past the wave's finish
    "Junior Open 15-16 #449: laps ours 4, theirs 5"           # rode a 5th lap after the juniors' finish opened
  ].freeze
end
