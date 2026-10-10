require "test_helper"

# Course races (point to point / single loop): start → checkpoints → finish, once.
class CourseTest < Minitest::Test
  include ResultsTestHelpers

  SETUP = <<~YAML
    races:
      - {id: r1, start: 0, course: [{id: a1, name: Aid 1, km: 30}, {id: a2, name: Aid 2, km: 60}], finish_km: 100}
    entrants:
      - {bib: 1, race: r1}
      - {bib: 2, race: r1}
      - {bib: 3, race: r1}
      - {bib: 4, race: r1}
  YAML

  def compute(yaml, now: 0) = Results.compute(input_from(SETUP + yaml + "now: #{now}\n"))
  def rows(out) = out.races.first.rows.map { [ it.place, it.bib, it.status.to_s, it.elapsed_ms&./(1000) ] }

  def test_finishers_place_by_time_from_the_gun_then_riders_still_out_by_how_far_they_got
    out = compute(<<~YAML)
      crossings:
        1: [{at: 900, cp: a1}, {at: 1800, cp: a2}, 3000]
        2: [{at: 800, cp: a1}, {at: 1700, cp: a2}, 2900]
        3: [{at: 1000, cp: a1}, {at: 2100, cp: a2}]
        4: [{at: 950, cp: a1}]
    YAML
    assert_equal [ [ 1, "2", "finished", 2900 ], [ 2, "1", "finished", 3000 ], [ 3, "3", "racing", 2100 ], [ 4, "4", "racing", 950 ] ], rows(out)
    assert_nil out.races.first.lap_count
  end

  def test_splits_give_clock_elapsed_and_segment_times_with_gaps_for_missed_checkpoints
    out = compute("crossings:\n  1: [{at: 900, cp: a1}, 3000]\n")
    splits = out.races.first.rows.find { it.bib == "1" }.splits
    assert_equal [ "a1", "a2", nil ], splits.map(&:checkpoint_id)
    assert_equal [ 900_000, nil, 3_000_000 ], splits.map(&:at_ms)
    assert_equal [ 900_000, nil, 2_100_000 ], splits.map(&:segment_ms) # from the last checkpoint they were seen at
  end

  def test_a_second_tap_at_a_checkpoint_is_a_duplicate_and_taps_before_the_start_or_after_the_finish_dont_count
    out = compute("crossings:\n  1: [{at: -5, cp: a1}, {at: 900, cp: a1}, {at: 960, cp: a1}, 3000, {at: 3100, cp: a2}]\n")
    row = out.races.first.rows.find { it.bib == "1" }
    assert_equal [ :before_start, :split, :duplicate, :finish, :after_finish ], row.crossings.map(&:kind)
    assert_equal [ "a1", "a1", "a1", nil, "a2" ], row.crossings.map(&:checkpoint_id)
  end

  def test_a_tap_at_a_checkpoint_and_the_finish_inside_the_debounce_window_both_count
    out = compute("crossings:\n  1: [{at: 100, cp: a1}, 105]\n")
    assert_equal [ 100_000, nil, 105_000 ], out.races.first.rows.find { it.bib == "1" }.splits.map(&:at_ms)
  end

  def test_pulls_and_statuses_work_as_on_laps
    out = compute(<<~YAML)
      crossings:
        1: [{at: 900, cp: a1}, {at: 1800, cp: a2}, 3000]
        2: [{at: 800, cp: a1}]
      rulings:
        - {kind: pull, bib: 1, at: 2000}
        - {kind: dnf, bib: 2}
    YAML
    by_bib = out.races.first.rows.to_h { [ it.bib, it ] }
    assert_equal :pulled, by_bib["1"].status
    assert_equal :after_pull, by_bib["1"].crossings.last.kind
    assert_equal :dnf, by_bib["2"].status
    assert_nil by_bib["2"].place
  end

  def test_an_inserted_crossing_fills_a_checkpoint
    out = compute("crossings:\n  1: [{at: 900, cp: a1}, 3000]\nrulings:\n  - {kind: insert_capture, bib: 1, at: 1900, cp: a2}\n")
    split = out.races.first.rows.first.splits[1]
    assert_equal [ 1_900_000, true ], [ split.at_ms, split.inserted ]
  end

  def test_not_started_and_in_progress_states
    assert_equal :not_started, Results.compute(input_from(SETUP.sub("start: 0, ", ""))).races.first.state
    assert_equal :in_progress, compute("crossings:\n  1: [{at: 900, cp: a1}]\n").races.first.state
    assert_equal :finish_open, compute("crossings:\n  1: [3000]\n").races.first.state
  end

  def test_a_laps_race_ignores_captures_taken_at_checkpoints
    yaml = setup_yaml(bibs: [ 1 ], laps: 3) + "crossings:\n  1: [100, {at: 150, cp: a1}, 200]\n"
    row = Results.compute(input_from(yaml)).races.first.rows.first
    assert_equal 2, row.laps
    assert_equal [], row.splits
  end
end
