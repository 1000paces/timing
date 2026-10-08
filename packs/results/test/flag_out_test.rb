require "test_helper"

# Flag out: from the moment the finish flag comes out for a wave, everyone
# finishes on their next crossing except the wave's leader, who rides on to
# the lap count (or, with no lap count, also finishes on their next crossing).
class FlagOutTest < Minitest::Test
  include ResultsTestHelpers

  def compute(yaml, laps: 4) = Results.compute(input_from(setup_yaml(bibs: [ 1, 2, 3 ], laps:) + yaml))
  def rows(out) = out.races.first.rows.map { [ it.bib, it.status.to_s, it.laps ] }

  CROSSINGS = "crossings:\n  1: [100, 200, 300, 400]\n  2: [100.6, 200.6, 300.6]\n  3: [150, 260]\n"

  def test_everyone_but_the_leader_finishes_on_their_next_crossing
    out = compute(CROSSINGS + "rulings:\n  - {kind: flag_out, race_id: r1, at: 210}\n")
    # 2 crossed 0.6 s behind the leader on every lap, but only the leader rides on to the lap count.
    assert_equal [ [ "1", "finished", 4 ], [ "2", "finished", 3 ], [ "3", "finished", 2 ] ], rows(out)
    assert_equal "finish_open", out.races.first.state.to_s
    assert_equal 210_000, out.races.first.flag_out_at_ms
  end

  def test_with_no_lap_count_the_leader_finishes_on_their_next_crossing_too
    out = compute(CROSSINGS + "rulings:\n  - {kind: flag_out, race_id: r1, at: 210}\n", laps: nil)
    assert_equal [ [ "1", "finished", 3 ], [ "2", "finished", 3 ], [ "3", "finished", 2 ] ], rows(out)
  end

  def test_undoing_the_flag_puts_everyone_back_on_the_lap_count
    yaml = CROSSINGS + "rulings:\n  - {id: f1, kind: flag_out, race_id: r1, at: 210}\n  - {kind: revert, ruling_id: f1}\n"
    out = compute(yaml)
    assert_equal [ [ "1", "finished", 4 ], [ "2", "racing", 3 ], [ "3", "racing", 2 ] ], rows(out)
    assert_nil out.races.first.flag_out_at_ms
  end

  def test_the_flag_covers_every_race_in_the_wave
    yaml = <<~YAML
      races:
        - {id: a, laps: 3, start: 0}
        - {id: b, laps: 3, start: 30}
      entrants:
        - {bib: 1, race: a}
        - {bib: 2, race: b}
      crossings:
        1: [100, 200, 300]
        2: [140, 250]
      rulings:
        - {kind: flag_out, race_id: a, at: 210}
    YAML
    out = Results.compute(input_from(yaml))
    assert_equal [ [ "1", "finished", 3 ], [ "2", "finished", 2 ] ], out.races.flat_map { |r| r.rows.map { [ it.bib, it.status.to_s, it.laps ] } }
  end

  def test_the_wave_leader_is_shown_and_is_never_a_rider_out_of_the_race
    flag = "  - {kind: flag_out, race_id: r1, at: 210}\n"
    out = compute(CROSSINGS + "rulings:\n" + flag)
    assert_equal "1", out.races.first.flag_out_leader

    # 1 was disqualified: 2 leads the wave on the road and rides on; the flag finishes 1, whose DSQ stands.
    out = compute(CROSSINGS + "rulings:\n  - {kind: dsq, bib: 1}\n" + flag)
    assert_equal "2", out.races.first.flag_out_leader
    assert_equal [ [ "1", "dsq", 3 ], [ "2", "racing", 3 ], [ "3", "finished", 2 ] ], rows(out).sort

    # A rider pulled before the flag can't lead it either.
    out = compute(CROSSINGS + "rulings:\n  - {kind: pull, bib: 1, at: 205}\n" + flag)
    assert_equal "2", out.races.first.flag_out_leader
  end

  def test_a_rider_who_has_not_crossed_long_after_the_flag_is_overdue
    # 3 rode 100 s laps and stopped at 310, before the flag at 320: overdue 150 s after that crossing.
    yaml = "crossings:\n  1: [100, 200, 300, 400]\n  3: [110, 210, 310]\n" \
           "rulings:\n  - {kind: flag_out, race_id: r1, at: 320}\n"
    overdue = ->(now) { Results.compute(input_from(setup_yaml(bibs: [ 1, 3 ], laps: 4) + yaml + "now: #{now}\n")).suggestions.select { it.kind == :overdue } }
    assert_empty overdue.(450), "3 crossed at 310: due back by 460"
    found = overdue.(470)
    assert_equal [ "3" ], found.map(&:bib)
    assert_equal({ "kind" => "dnf", "bib" => "3" }, found.first.fix)
    assert_match(/Bib 3 hasn't crossed since/, found.first.message)
  end

  def test_nobody_is_overdue_before_the_finish_opens
    yaml = "crossings:\n  1: [100, 200]\n  2: [110]\nnow: 1000\n"
    assert_empty Results.compute(input_from(setup_yaml(bibs: [ 1, 2 ], laps: 5) + yaml)).suggestions.select { it.kind == :overdue }
  end
end
