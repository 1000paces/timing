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
end
