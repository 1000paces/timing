require "test_helper"

class ResolverTest < Minitest::Test
  include ResultsTestHelpers

  def resolve(yaml) = Results::Resolver.new(input_from(setup_yaml + yaml)).call

  def times(resolved, bib) = resolved.crossings_by_bib.fetch(bib.to_s, []).map { it.at_ms / 1000 }

  def test_capture_bib_maps_to_crossings_sorted_by_time
    r = resolve("crossings:\n  1: [600, 300]\n")
    assert_equal [300, 600], times(r, 1)
  end

  def test_clock_offset_is_applied_and_missing_offset_flags_device
    r = resolve(<<~YAML)
      captures:
        - {id: a, bib: 1, at: 300, device: d1, offset_ms: 2000}
        - {id: b, bib: 2, at: 300, device: d2, offset_ms: ~}
    YAML
    assert_equal [302], times(r, 1)
    assert_equal [300], times(r, 2)
    assert_equal ["d2"], r.unsynced_devices
  end

  def test_device_bib_assignment_names_a_bibless_tap
    r = resolve("unassigned: [300]\nbib_assignments:\n  - {id: b-1, capture: u-1, bib: 2}\n")
    assert_equal [300], times(r, 2)
    assert_empty r.unassigned
  end

  def test_assign_bib_ruling_overrides_device_assignment
    r = resolve(<<~YAML)
      unassigned: [300]
      bib_assignments:
        - {id: b-1, capture: u-1, bib: 2}
      rulings:
        - {kind: assign_bib, capture_id: u-1, bib: 3}
    YAML
    assert_equal [], times(r, 2)
    assert_equal [300], times(r, 3)
  end

  def test_void_removes_and_insert_adds
    r = resolve(<<~YAML)
      crossings:
        1: [300, 600]
      rulings:
        - {kind: void_capture, capture_id: c-1-2}
        - {id: ins, kind: insert_capture, bib: 1, at: 900}
    YAML
    assert_equal [300, 900], times(r, 1)
    assert r.crossings_by_bib["1"].last.inserted
  end

  # Review Focus 5: a typo'd bib is kept, visible, and unassigned.
  def test_assign_bib_to_unregistered_bib_goes_to_unassigned_with_that_bib
    r = resolve("crossings:\n  1: [300]\nrulings:\n  - {kind: assign_bib, capture_id: c-1-1, bib: 999}\n")
    assert_equal [], times(r, 1)
    assert_equal [Results::UnassignedCrossing.new(capture_id: "c-1-1", at_ms: 300_000, bib: "999")], r.unassigned
  end

  # Review Focus 4: reverting a revert restores the original ruling.
  def test_revert_of_revert_restores_original
    r = resolve(<<~YAML)
      crossings:
        1: [300, 600]
      rulings:
        - {id: v, kind: void_capture, capture_id: c-1-2, created: 700}
        - {id: rv, kind: revert, ruling_id: v, created: 800}
        - {id: rrv, kind: revert, ruling_id: rv, created: 900}
    YAML
    assert_equal [300], times(r, 1)
  end

  def test_single_revert_cancels_ruling
    r = resolve(<<~YAML)
      crossings:
        1: [300, 600]
      rulings:
        - {id: v, kind: void_capture, capture_id: c-1-2, created: 700}
        - {id: rv, kind: revert, ruling_id: v, created: 800}
    YAML
    assert_equal [300, 600], times(r, 1)
  end

  def test_taps_within_debounce_window_collapse_to_earliest
    r = resolve(<<~YAML)
      captures:
        - {id: a, bib: 1, at: 300, device: d1}
        - {id: b, bib: 1, at: 306, device: d2}
        - {id: c, bib: 1, at: 600, device: d1}
    YAML
    assert_equal [300, 600], times(r, 1)
    assert_equal({ "b" => "a" }, r.aliases)
  end

  def test_latest_by_uses_chronological_order_not_input_order
    rulings = Results::ActiveRulings.new([
      Results::Ruling.new(id: "late", kind: "set_lap_count", payload: { "race_id" => "r1", "laps" => 5 }, created_at_ms: 900),
      Results::Ruling.new(id: "early", kind: "set_lap_count", payload: { "race_id" => "r1", "laps" => 6 }, created_at_ms: 600)
    ])
    assert_equal "late", rulings.latest_by("set_lap_count") { it.payload["race_id"] }["r1"].id
  end

  def test_cancelled_ids_lists_reverted_rulings_including_reverted_reverts
    rulings = Results::ActiveRulings.new([
      Results::Ruling.new(id: "v", kind: "void_capture", payload: { "capture_id" => "c" }, created_at_ms: 1),
      Results::Ruling.new(id: "rv", kind: "revert", payload: { "ruling_id" => "v" }, created_at_ms: 2),
      Results::Ruling.new(id: "d", kind: "dnf", payload: { "bib" => "1" }, created_at_ms: 3),
      Results::Ruling.new(id: "rd", kind: "revert", payload: { "ruling_id" => "d" }, created_at_ms: 4),
      Results::Ruling.new(id: "rrd", kind: "revert", payload: { "ruling_id" => "rd" }, created_at_ms: 5)
    ])
    assert_equal Set["v", "rd"], rulings.cancelled_ids
  end
end
