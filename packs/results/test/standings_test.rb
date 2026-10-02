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

  def test_race_reports_its_effective_start
    assert_nil race(compute("crossings:\n  1: [100]\n", gun: nil)).start_at_ms
    assert_equal 100_000, race(compute("crossings:\n  1: [300]\n", gun: 100)).start_at_ms
    out = compute("rulings:\n  - {kind: set_race_start, race_id: r1, at: 30}\n", gun: nil)
    assert_equal 30_000, race(out).start_at_ms
  end

  def test_set_race_start_overrides_group_gun
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

  TWO_GROUPS = <<~YAML
    start_groups:
      - {id: g1, finish_rule: {type: fixed_laps, laps: 3}, gun: 0}
      - {id: g2, finish_rule: {type: fixed_laps, laps: 3}, gun: 0}
    races:
      - {id: r1, group: g1}
      - {id: r2, group: g2}
  YAML

  def two_groups(entrants:, crossings:, rulings: "")
    yaml = TWO_GROUPS + "entrants:\n" + entrants.map { |bib, race| "  - {bib: #{bib}, race: #{race}}\n" }.join
    yaml += "crossings:\n" + crossings.map { |bib, times| "  #{bib}: #{times}\n" }.join
    yaml += "rulings:\n" + rulings unless rulings.empty?
    Results.compute(input_from(yaml))
  end

  def publication(out, race_id = "r1") = out.races.find { it.race_id == race_id }.publication
  def publish_line(out, race_id = "r1") = "  - {kind: publish_results, race_id: #{race_id}, result_digest: #{out.races.find { it.race_id == race_id }.digest}}\n"

  def test_publication_lifecycle
    entrants = [[1, "r1"], [2, "r1"], [3, "r2"]]
    crossings = { 1 => "[100, 200, 300]", 2 => "[110, 220]", 3 => "[150]" }
    base = two_groups(entrants:, crossings:)
    assert_equal :provisional, publication(base)
    assert_match(/\A\h{64}\z/, base.races.first.digest)

    published = publish_line(base)
    assert_equal :published, publication(two_groups(entrants:, crossings:, rulings: published))
  end

  def test_other_races_changes_do_not_unpublish
    entrants = [[1, "r1"], [2, "r1"], [3, "r2"]]
    crossings = { 1 => "[100, 200, 300]", 2 => "[110, 220]", 3 => "[150]" }
    published = publish_line(two_groups(entrants:, crossings:))
    more = crossings.merge(3 => "[150, 250]")
    out = two_groups(entrants:, crossings: more, rulings: published)
    assert_equal :published, publication(out)
    assert_equal :provisional, publication(out, "r2")
  end

  def test_changed_rows_mark_changed_since_published
    entrants = [[1, "r1"], [2, "r1"], [3, "r2"]]
    crossings = { 1 => "[100, 200, 300]", 2 => "[110, 220]", 3 => "[150]" }
    published = publish_line(two_groups(entrants:, crossings:))
    out = two_groups(entrants:, crossings: crossings.merge(2 => "[110, 220, 330]"), rulings: published)
    assert_equal :changed_since_published, publication(out)
  end

  def test_setup_change_marks_changed_since_published
    entrants = [[1, "r1"], [2, "r1"], [3, "r2"]]
    crossings = { 1 => "[100, 200, 300]", 2 => "[110, 220]", 3 => "[150]" }
    published = publish_line(two_groups(entrants:, crossings:))
    out = two_groups(entrants: [[1, "r1"], [3, "r2"], [2, "r2"]], crossings:, rulings: published)
    assert_equal :changed_since_published, publication(out)
  end

  def test_set_lap_count_overrides_fixed_laps_rule
    out = compute(<<~YAML, bibs: [1, 2], finish_rule: "{type: fixed_laps, laps: 5}")
      crossings:
        1: [100, 200, 300, 400, 500]
        2: [110, 220, 330]
      rulings:
        - {kind: set_lap_count, start_group_id: g1, laps: 3}
    YAML
    assert_equal 3, race(out).lap_count
    assert_equal [[1, "1", "finished", 3, 300], [2, "2", "finished", 3, 330]], rows(out)
  end

  def test_pull_after_finish_is_ignored
    out = compute("crossings:\n  1: [100, 200, 300]\n  2: [110, 220]\nrulings:\n  - {kind: pull, bib: 1, at: 300}\n  - {kind: pull, bib: 2, at: 400}\n")
    assert_equal [1, "1", "finished", 3, 300], rows(out).first
  end

  def test_pull_before_finish_still_wins
    out = compute("crossings:\n  1: [100, 200, 300]\n  2: [110, 220]\nrulings:\n  - {kind: pull, bib: 1, at: 250}\n")
    assert_equal ["1", "pulled", 2, 200], rows(out).find { it[1] == "1" }[1..]
  end
end
