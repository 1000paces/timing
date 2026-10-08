require "test_helper"

# What a racer panel shows: every crossing with what it counted as, positions
# at the end of each lap, and the pull / finish markers.
class RacerDetailTest < Minitest::Test
  include ResultsTestHelpers

  def compute(yaml, **setup) = Results.compute(input_from(setup_yaml(**setup) + yaml))
  def racer(out, bib) = out.races.flat_map(&:rows).find { it.bib == bib.to_s }
  def views(row) = row.crossings.map { [it.ref, it.kind.to_s, it.lap, it.lap_ms] }

  def test_each_crossing_says_what_it_counted_as
    out = compute("crossings:\n  1: [5, 100, 200, 203, 300, 400]\n", bibs: [1], laps: 3, start: 10)
    row = racer(out, 1)
    assert_equal [["c-1-1", "before_start", nil, nil], ["c-1-2", "lap", 1, 90_000], ["c-1-3", "lap", 2, 100_000],
                  ["c-1-4", "duplicate", nil, nil], ["c-1-5", "finish", 3, 100_000], ["c-1-6", "after_finish", nil, nil]], views(row)
    assert_equal "c-1-5", row.finish_ref
    assert_nil row.pull_at_ms
  end

  def test_positions_at_the_end_of_each_lap
    yaml = "crossings:\n  1: [100, 200, 300]\n  2: [90, 210]\n  3: [100, 190, 280]\n"
    out = compute(yaml, bibs: [1, 2, 3], laps: nil)
    assert_equal [2, 2, 2], racer(out, 1).lap_positions, "a tie at lap 1 goes to the lower crossing ref"
    assert_equal [1, 3], racer(out, 2).lap_positions
    assert_equal [3, 1, 1], racer(out, 3).lap_positions
  end

  # Review Focus 3
  def test_a_pull_between_crossings
    out = compute("crossings:\n  1: [100, 200, 300]\nrulings:\n  - {kind: pull, bib: 1, at: 250}\n", bibs: [1], laps: nil)
    row = racer(out, 1)
    assert_equal ["lap", "lap", "after_pull"], row.crossings.map { it.kind.to_s }
    assert_equal 250_000, row.pull_at_ms
    assert_equal [1, 1], row.lap_positions
  end

  # Review Focus 1
  def test_a_finish_flag_on_a_crossing_moved_to_another_bib_is_ignored
    yaml = "crossings:\n  1: [100, 200]\n  2: [110]\nrulings:\n" \
           "  - {kind: flag_finish, bib: 1, capture_id: c-1-2}\n  - {kind: assign_bib, capture_id: c-1-2, bib: 2}\n"
    out = compute(yaml, bibs: [1, 2], laps: nil)
    assert_nil racer(out, 1).finish_ref
    assert_equal [["c-1-1", "lap", 1, 100_000]], views(racer(out, 1))
  end

  # Review Focus 2
  def test_an_insert_on_top_of_a_tap_shows_as_one_duplicate
    out = compute("crossings:\n  1: [100, 200]\nrulings:\n  - {id: ins, kind: insert_capture, bib: 1, at: 203}\n", bibs: [1], laps: nil)
    row = racer(out, 1)
    assert_equal [["c-1-1", "lap"], ["c-1-2", "lap"], ["ins", "duplicate"]], row.crossings.map { [it.ref, it.kind.to_s] }
    assert row.crossings.last.inserted
  end
end
