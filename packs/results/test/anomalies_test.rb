require "test_helper"

class AnomaliesTest < Minitest::Test
  include ResultsTestHelpers

  # Three riders, 5 laps of ~300s. Bib 2 misses lap 3's crossing; bib 3 misses lap 4's.
  MISSED = <<~YAML
    crossings:
      1: [300, 600, 900, 1200, 1500]
      2: [310, 620, 1240, 1550]
      3: [305, 610, 915, 1525]
  YAML

  def compute(yaml, **setup) = Results.compute(input_from(setup_yaml(**setup) + yaml))
  def find(out, key) = out.suggestions.find { it.key == key }

  def test_missed_crossing_prefers_matching_unassigned_capture
    out = compute(MISSED + "unassigned: [935]\n", laps: 5)
    assert_equal ["missed:2:c-2-2:c-2-3", "missed:3:c-3-3:c-3-4", "unassigned:u-1"], out.suggestions.map(&:key)
    assert_equal({ "kind" => "assign_bib", "capture_id" => "u-1", "bib" => "2" }, find(out, "missed:2:c-2-2:c-2-3").fix)
    assert_equal({ "kind" => "insert_capture", "bib" => "3", "at_ms" => 1_220_000 }, find(out, "missed:3:c-3-3:c-3-4").fix)
    assert_equal :suspected_missed_crossing, find(out, "missed:3:c-3-3:c-3-4").kind
  end

  def test_accepting_the_suggestion_fixes_laps_and_clears_it
    yaml = MISSED + "unassigned: [935]\nrulings:\n  - {kind: assign_bib, capture_id: u-1, bib: 2}\n"
    out = compute(yaml, laps: 5)
    refute find(out, "missed:2:c-2-2:c-2-3")
    assert_equal [2, "2", "finished", 5, 1550], compact_rows(out.races.first.rows).find { it[1] == "2" }
  end

  def test_dismissed_suggestions_are_suppressed
    yaml = MISSED + "rulings:\n  - {kind: dismiss_suggestion, suggestion_key: \"missed:3:c-3-3:c-3-4\"}\n"
    out = compute(yaml, laps: 5)
    refute find(out, "missed:3:c-3-3:c-3-4")
    assert find(out, "missed:2:c-2-2:c-2-3")
  end

  def test_short_lap_suggests_voiding_the_extra_crossing
    out = compute("crossings:\n  1: [300, 600, 700, 900, 1200]\n  2: [310, 620, 930, 1240]\n", bibs: [1, 2], laps: 10)
    short = out.suggestions.select { it.kind == :suspected_duplicate }
    assert_includes short.map(&:key), "short:1:c-1-2:c-1-3"
    assert_equal({ "kind" => "void_capture", "capture_id" => "c-1-3" }, find(out, "short:1:c-1-2:c-1-3").fix)
  end

  def test_short_start_loop_is_not_flagged
    # XC-style: the start loop is about half a lap for everyone.
    out = compute("crossings:\n  1: [150, 450, 750]\n  2: [155, 460, 765]\n  3: [160, 470, 780]\n", laps: 10)
    assert_empty out.suggestions
  end

  def test_slow_rider_is_not_flagged_as_missing_crossings
    out = compute("crossings:\n  1: [100, 200, 300, 400]\n  2: [190, 380, 570]\n", bibs: [1, 2], laps: 20)
    assert_empty out.suggestions.reject { it.kind == :about_to_be_lapped }
  end

  def test_about_to_be_lapped_uses_projected_positions
    crossings = "crossings:\n  1: [#{(1..10).map { it * 100 }.join(', ')}]\n  2: [190, 380, 570, 760, 950]\n  3: [#{(1..10).map { it * 105 }.join(', ')}]\n"
    out = compute("now: 1050\n" + crossings, laps: 20)
    assert_equal ["lapped:2:5"], out.suggestions.map(&:key)
    assert_equal({ "kind" => "flag_finish", "bib" => "2" }, out.suggestions.first.fix)
  end

  def test_no_lapping_suggestions_once_finish_is_open
    out = compute("now: 400\ncrossings:\n  1: [100, 200, 300]\n  2: [190]\n")
    assert_empty out.suggestions.select { it.kind == :about_to_be_lapped }
  end

  def test_unsynced_clock_is_reported_per_device
    out = compute(<<~YAML)
      captures:
        - {id: a, bib: 1, at: 100, device: d2, offset_ms: ~}
        - {id: b, bib: 2, at: 110, device: d2, offset_ms: ~}
    YAML
    assert_equal ["clock:d2"], out.suggestions.map(&:key)
  end

  def test_missed_crossing_does_not_cause_false_short_suggestion_on_neighbour
    others = "  1: [300, 600, 900, 1200]\n  3: [305, 610, 915, 1220]\n"
    {
      [300, 600, 1210] => "missed:2:c-2-2:c-2-3",
      [300, 910, 1210] => "missed:2:c-2-1:c-2-2",
      [300, 600, 1320] => nil
    }.each do |times, missed_key|
      out = compute("crossings:\n#{others}  2: [#{times.join(', ')}]\n", laps: 10)
      assert_empty out.suggestions.select { it.key.start_with?("short:2:") }, "short for #{times}"
      assert find(out, missed_key), "missed for #{times}" if missed_key
    end
  end
end
