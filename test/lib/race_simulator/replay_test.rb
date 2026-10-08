require "test_helper"

class RaceSimulator::ReplayTest < ActiveSupport::TestCase
  DATASET = RaceSimulator::Replay::Dataset.load("cascade_locks_1")

  test "the dataset has every racer of the real results, each category in exactly one wave" do
    assert_equal 219, DATASET.results.size
    assert_equal 34, DATASET.races.size
    assert_equal DATASET.results.map(&:category).uniq.sort, DATASET.races.map(&:name).sort
    cat4 = DATASET.results.find { it.bib == "381" }
    assert_equal [ "Category 4 Open", 1, 6 ], [ cat4.category, cat4.place, cat4.laps ]
    assert_equal [ 428_960, 445_980 ], cat4.laps_ms.first(2)
    assert_equal [ 561_000, 577_000 ], DATASET.results.find { it.bib == "243" }.laps_ms # the running race is in h:mm:ss
  end

  test "each wave's lap count is its leader's, and its flag time comes from the data" do
    wave = DATASET.waves.find { it.gun == "11:00" }
    assert_equal 7, wave.lap_count(DATASET.results_for(wave.races.map(&:name))) # #43
    assert_equal 2330, wave.flag_out_s
    assert_nil DATASET.waves.first.flag_out_s
  end

  test "setup builds the real event: races in waves, real bibs, made-up names, Pacific time" do
    event = RaceSimulator::Replay.setup!(DATASET)
    assert_equal [ "Cross Crusade Cascade Locks 1", Date.new(2026, 9, 27), "America/Los_Angeles", "cyclocross" ], [ event.name, event.date, event.timezone, event.discipline ]
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
    assert_equal KNOWN_MISMATCHES.sort, check.mismatches.map(&:to_s).sort
    assert_equal %w[143 292 379 421 422 423 46], check.stopped_early.map(&:bib).sort # quit early: the chief marks DNF
    assert_equal check.stopped_early.size, check.stopped_early.map(&:bib).uniq.size
  end

  test "a second real race replays with the same rules and the fitted waves" do
    dataset = RaceSimulator::Replay::Dataset.load("cascade_locks_2")
    event = RaceSimulator::Replay.setup!(dataset)
    RaceSimulator::Replay.run(event:, dataset:, speed: 0, out: StringIO.new)
    check = RaceSimulator::Replay::Check.new(event:, dataset:)
    assert_equal 34, check.races_checked
    assert_equal [
      "Masters 50+ #330: laps ours 5, theirs 6",          # rode on 4 s after #402 stopped: one of them is off the flag
      "Masters 60+ #46: laps ours 4, theirs 5",           # a 6:06 last lap after ~10:00 laps, after the flag (as at race 1)
      "Masters 60+ #46: place ours 11, theirs 10",
      "Masters 60+ #487: place ours 10, theirs 11",
      "Masters Women 70+ #472: laps ours 3, theirs 4"     # a 4:50 last lap after ~14:00 laps, after the flag
    ], check.mismatches.map(&:to_s).sort
    assert_equal %w[273 316 400 513 536 69], check.stopped_early.map(&:bib).sort
  end

  test "the fitter recovers race 1's arming delays and flag times from its results" do
    fitted = RaceSimulator::Replay::Fit.new(DATASET).waves
    assert_equal DATASET.waves.map(&:arm_s), fitted.map(&:arm_s)
    DATASET.waves.zip(fitted).select { it.first.flag_out_s && it.first.gun != "13:55" }.each do |mine, fit|
      assert_in_delta mine.flag_out_s, fit.flag_out_s, 5, "#{mine.gun} wave" # juniors: the data allows 27:56 to 29:03
    end
  end

  # What the real event did that the hub's rules don't: everything else
  # (places, laps, every lap time) matches the published results.
  KNOWN_MISMATCHES = [
    "Category 3 Masters Open 35+ #386: laps ours 5, theirs 6", # rode on after the flag, with a 4:28 last lap (normal: 8:00)
    "Category 3 Masters Open 35+ #386: place ours 16, theirs 8", # ...so we place him on 5 laps,
    *%w[21:8:9 390:9:10 257:10:11 435:11:12 55:12:13 304:13:14 416:14:15 326:15:16].map do |entry| # and those between move up one
      bib, ours, theirs = entry.split(":")
      "Category 3 Masters Open 35+ ##{bib}: place ours #{ours}, theirs #{theirs}"
    end,
    "Junior Open 13-14 #70: laps ours 3, theirs 4",           # rode on after the juniors' flag; a 6:49 last lap after a 10:46
    "Junior Women 11-12 #324: laps ours 3, theirs 4"          # rode on after the juniors' flag (or our junior start offsets are off)
  ].freeze
end
