require "test_helper"

class StandingsTest < Minitest::Test
  include ResultsTestHelpers

  def compute(yaml, **setup) = Results.compute(input_from(setup_yaml(**setup) + yaml))
  def race(out) = out.races.find { it.race_id == "r1" }
  def rows(out) = compact_rows(race(out).rows)

  def test_fixed_laps_finish_opens_on_leader_and_ranks_by_laps_then_time
    out = compute("crossings:\n  1: [100, 200, 300]\n  2: [110, 220, 330]\n  3: [150, 310]\n")
    assert_equal [[1, "1", "finished", 3, 300], [2, "2", "finished", 3, 330], [3, "3", "finished", 2, 310]], rows(out)
    assert_equal :finish_open, race(out).state
  end

  def test_timed_group_without_lap_count_is_in_progress_ranked_live
    out = compute("crossings:\n  1: [100, 200]\n  2: [110]\n  3: [105, 215]\n", finish_rule: "{type: timed, target_duration_ms: 2700000}")
    assert_equal :in_progress, race(out).state
    assert_nil race(out).lap_count
    assert_equal [[1, "1", "racing", 2, 200], [2, "3", "racing", 2, 215], [3, "2", "racing", 1, 110]], rows(out)
  end

  # Review Focus 2
  def test_no_gun_means_not_started_and_crossings_do_not_count
    out = compute("crossings:\n  1: [100, 200]\n", gun: nil)
    assert_equal :not_started, race(out).state
    assert_equal [[1, "1", "racing", 0, nil], [2, "2", "racing", 0, nil], [3, "3", "racing", 0, nil]], rows(out)
  end

  def test_crossings_before_race_start_are_ignored
    out = compute("crossings:\n  1: [50, 150, 250, 350]\n", gun: 100)
    assert_equal [1, "1", "finished", 3, 250], rows(out).first
  end

  # Review Focus 1
  def test_identical_times_tie_break_deterministically_by_crossing_id
    out = compute("crossings:\n  2: [100]\n  1: [100]\n", bibs: [1, 2], finish_rule: "{type: fixed_laps, laps: 1}")
    assert_equal ["1", "2"], race(out).rows.map(&:bib)
  end

  # Review Focus 3
  def test_flag_finish_on_voided_capture_is_ignored
    out = compute(<<~YAML)
      crossings:
        1: [100, 200, 300]
        2: [180, 360]
      rulings:
        - {kind: void_capture, capture_id: c-2-1}
        - {kind: flag_finish, bib: 2, capture_id: c-2-1}
    YAML
    assert_equal [2, "2", "finished", 1, 360], rows(out)[1]
  end

  def test_flag_finish_follows_debounced_alias
    out = compute(<<~YAML, bibs: [1, 2])
      crossings:
        1: [100, 200, 300]
      captures:
        - {id: a, bib: 2, at: 180}
        - {id: b, bib: 2, at: 185, device: d2}
      rulings:
        - {kind: flag_finish, bib: 2, capture_id: b}
    YAML
    assert_equal [2, "2", "finished", 1, 180], rows(out)[1]
  end

  def test_set_race_start_overrides_group_gun_plus_offset
    out = compute("crossings:\n  1: [130, 230, 330]\nrulings:\n  - {kind: set_race_start, race_id: r1, at: 30}\n", bibs: [1])
    assert_equal [1, "1", "finished", 3, 300], rows(out).first
  end

  def test_gap_and_lap_times
    out = compute("crossings:\n  1: [100, 200, 300]\n  2: [110, 220, 340]\n  3: [150, 310]\n")
    leader, second, third = race(out).rows
    assert_nil leader.gap
    assert_equal Results::Gap.new(laps_down: 0, ms: 40_000), second.gap
    assert_equal Results::Gap.new(laps_down: 1, ms: nil), third.gap
    assert_equal [110_000, 110_000, 120_000], second.lap_times_ms
  end

  def test_statuses_rank_after_placed_riders_without_places
    out = compute(<<~YAML, bibs: [1, 2, 3, 4])
      crossings:
        1: [100, 200, 300]
        4: [120]
      rulings:
        - {kind: dsq, bib: 4}
        - {kind: dns, bib: 3}
        - {kind: dnf, bib: 2}
    YAML
    assert_equal [[1, "1", "finished", 3, 300], [nil, "2", "dnf", 0, nil], [nil, "3", "dns", 0, nil], [nil, "4", "dsq", 1, nil]], rows(out)
  end

  def test_publication_lifecycle
    yaml = "crossings:\n  1: [100, 200, 300]\n"
    first = compute(yaml)
    assert_equal :provisional, race(first).publication
    published = yaml + "rulings:\n  - {kind: publish_results, race_id: r1, log_digest: #{first.log_digest}}\n"
    assert_equal :published, race(compute(published)).publication
    changed = published + "unassigned: [400]\n"
    assert_equal :changed_since_published, race(compute(changed)).publication
  end
end
