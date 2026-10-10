require "test_helper"

class CourseAnomaliesTest < Minitest::Test
  include ResultsTestHelpers

  # Gun at 0; Aid 1 at 30 km, Aid 2 at 60 km (cutoff 2:30 elapsed), finish at 100 km.
  SETUP = <<~YAML
    races:
      - {id: r1, start: 0, course: [{id: a1, name: Aid 1, km: 30}, {id: a2, name: Aid 2, km: 60, cutoff: 9000}], finish_km: 100}
    entrants:
      - {bib: 1, race: r1}
      - {bib: 2, race: r1}
      - {bib: 3, race: r1}
      - {bib: 4, race: r1}
  YAML

  def suggestions(yaml, now:) = Results.compute(input_from(SETUP + yaml + "now: #{now}\n")).suggestions

  def test_a_rider_seen_later_but_not_at_a_checkpoint_gets_an_insert_interpolated_by_distance
    found = suggestions("crossings:\n  1: [{at: 3000, cp: a1}, 10000]\n", now: 10_000).find { it.kind == :missed_checkpoint }
    assert_equal "missed_checkpoint:1:a2", found.key
    # 30 km at 3000 s, 100 km at 10000 s: 60 km at 6000 s.
    assert_equal({ "kind" => "insert_capture", "bib" => "1", "at_ms" => 6_000_000, "checkpoint_id" => "a2" }, found.fix)
    assert_match(/Aid 2/, found.message)
  end

  def test_without_distances_the_insert_is_the_midpoint
    yaml = SETUP.gsub(/, km: \d+/, "").sub(", finish_km: 100", "")
    found = Results.compute(input_from(yaml + "crossings:\n  1: [{at: 3000, cp: a1}, 10000]\nnow: 10000\n")).suggestions
                   .find { it.kind == :missed_checkpoint }
    assert_equal 6_500_000, found.fix["at_ms"]
  end

  def test_overdue_from_the_riders_own_pace
    # 30 km in 3000 s: 30 more km should take 3000 s; overdue after 1.5x that (7500 s), and past the cutoff too.
    assert_empty suggestions("crossings:\n  1: [{at: 3000, cp: a1}]\n", now: 7_400).select { it.kind == :overdue }
    found = suggestions("crossings:\n  1: [{at: 3000, cp: a1}]\n", now: 7_600).find { it.kind == :overdue }
    assert_equal [ "overdue:1:c-1-1", { "kind" => "dnf", "bib" => "1" } ], [ found.key, found.fix ]
  end

  def test_overdue_from_the_field_when_there_are_no_distances
    yaml = SETUP.gsub(/, km: \d+/, "").sub(", finish_km: 100", "").sub(", cutoff: 9000", "")
    crossings = "crossings:\n  1: [{at: 1000, cp: a1}, {at: 2000, cp: a2}]\n  2: [{at: 1000, cp: a1}, {at: 2100, cp: a2}]\n" \
                "  3: [{at: 1000, cp: a1}, {at: 2200, cp: a2}]\n  4: [{at: 1000, cp: a1}]\n"
    found = Results.compute(input_from(yaml + crossings + "now: 2700\n")).suggestions.select { it.kind == :overdue }
    assert_equal [ "4" ], found.map(&:bib) # field median 1100 s × 1.5 = 1650 s after 1000 s
    assert_empty Results.compute(input_from(yaml + "crossings:\n  4: [{at: 1000, cp: a1}]\nnow: 99000\n")).suggestions.select { it.kind == :overdue }
  end

  def test_cutoff_missed_or_reached_late_suggests_a_pull_at_the_cutoff
    late = suggestions("crossings:\n  1: [{at: 3000, cp: a1}, {at: 9500, cp: a2}]\n", now: 9_600).find { it.kind == :cutoff }
    assert_equal [ "cutoff:1:a2", { "kind" => "pull", "bib" => "1", "at_ms" => 9_000_000 } ], [ late.key, late.fix ]
    assert suggestions("crossings:\n  1: [{at: 3000, cp: a1}]\n", now: 9_100).any? { it.kind == :cutoff }
    assert_empty suggestions("crossings:\n  1: [{at: 3000, cp: a1}]\n", now: 8_900).select { it.kind == :cutoff }
  end

  def test_a_rider_pulled_at_the_cutoff_who_taps_the_finish_stays_pulled_with_no_new_problems
    yaml = "crossings:\n  1: [{at: 3000, cp: a1}, {at: 9500, cp: a2}, 12000]\nrulings:\n  - {kind: pull, bib: 1, at: 9000}\n"
    out = Results.compute(input_from(SETUP + yaml + "now: 12100\n"))
    assert_equal :pulled, out.races.first.rows.find { it.bib == "1" }.status
    assert_empty out.suggestions.select { it.bib == "1" }
  end

  def test_finished_and_dnf_riders_raise_nothing
    yaml = "crossings:\n  1: [{at: 3000, cp: a1}, {at: 6000, cp: a2}, 10000]\n  2: [{at: 3000, cp: a1}]\nrulings:\n  - {kind: dnf, bib: 2}\n"
    assert_empty suggestions(yaml, now: 99_000).select { %w[1 2].include?(it.bib) }
  end
end
