require "test_helper"

class RaceSimulator::CourseReplayTest < ActiveSupport::TestCase
  DATASET = RaceSimulator::CourseReplay.load("gravel_demo")

  test "setup builds a course event with its checkpoints, cutoff and finish distance" do
    event = RaceSimulator::CourseReplay.setup!(DATASET)
    assert event.course?
    assert_equal [ [ "Aid 1", 30 ], [ "Aid 2", 62 ] ], event.checkpoints.map { [ it.name, it.distance_km.to_i ] }
    zone = Time.find_zone("America/Los_Angeles")
    assert_equal zone.parse("2026-10-17 10:30").to_i * 1000, event.checkpoints.last.cutoff_at_ms
    assert_equal 100, event.finish_distance_km.to_i
  end

  test "five hours in: places, splits and the expected problems" do
    event = RaceSimulator::CourseReplay.setup!(DATASET)
    RaceSimulator::CourseReplay.run(event:, dataset: DATASET, out: StringIO.new)
    gun = Time.find_zone("America/Los_Angeles").parse("2026-10-17 08:00").to_i * 1000
    output = ResultsSnapshot.compute(event, now_ms: gun + 5 * 3_600_000)
    rows = output.races.first.rows
    assert_equal [ [ 1, "105", :finished ], [ 2, "101", :finished ], [ 3, "102", :finished ], [ 4, "103", :racing ], [ 5, "104", :racing ] ],
                 rows.map { [ it.place, it.bib, it.status ] }
    assert_equal [ 3_720_000, 7_500_000, 12_000_000 ], rows.first.splits.map(&:elapsed_ms)
    problems = output.suggestions.map { [ it.kind, it.bib ] }.sort
    assert_equal [ [ :cutoff, "103" ], [ :cutoff, "104" ], [ :missed_checkpoint, "102" ], [ :overdue, "104" ] ], problems
  end
end
