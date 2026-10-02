require "test_helper"

class RulingShapeTest < Minitest::Test
  include ResultsTestHelpers

  def compute(yaml, **setup) = Results.compute(input_from(setup_yaml(**setup) + yaml))
  def ruling(kind, payload) = Results::Ruling.new(id: "x", kind:, payload:, created_at_ms: 0)

  def test_accepts_well_typed_rulings
    assert Results::RulingShape.valid?(ruling("set_lap_count", { "race_id" => "r1", "laps" => 3 }))
    assert Results::RulingShape.valid?(ruling("pull", { "bib" => "2", "at_ms" => 5 }))
  end

  def test_rejects_bad_types_and_unknown_kinds
    refute Results::RulingShape.valid?(ruling("set_lap_count", { "race_id" => "r1", "laps" => "3" }))
    refute Results::RulingShape.valid?(ruling("set_lap_count", { "race_id" => "r1", "laps" => 0 }))
    refute Results::RulingShape.valid?(ruling("insert_capture", { "bib" => "1", "at_ms" => nil }))
    refute Results::RulingShape.valid?(ruling("set_race_start", { "race_id" => "r1", "at_ms" => "5" }))
    refute Results::RulingShape.valid?(ruling("dnf", { "bib" => " " }))
    refute Results::RulingShape.valid?(ruling("teleport", {}))
  end

  def test_malformed_lap_count_is_ignored_and_standings_compute
    out = compute(<<~YAML, laps: nil)
      crossings:
        1: [100, 200]
        2: [110]
      rulings:
        - {kind: set_lap_count, race_id: r1, laps: "1"}
        - {kind: set_lap_count, race_id: r1, laps: 0}
    YAML
    race = out.races.find { it.race_id == "r1" }
    assert_nil race.lap_count
    assert_equal :in_progress, race.state
  end

  def test_malformed_insert_capture_is_ignored
    out = compute(<<~YAML, bibs: [1])
      crossings:
        1: [100, 200, 300]
      rulings:
        - {id: bad, kind: insert_capture, bib: 1, at: null}
        - {id: v1, kind: void_capture, capture_id: c-1-3}
        - {id: bad2, kind: void_capture, capture_id: 7}
    YAML
    race = out.races.find { it.race_id == "r1" }
    assert_equal [[1, "1", "racing", 2, 200]], compact_rows(race.rows)
  end
end
