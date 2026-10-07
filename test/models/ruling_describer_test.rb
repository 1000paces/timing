require "test_helper"

class RulingDescriberTest < ActiveSupport::TestCase
  test "each kind reads as one line, with times in the event's time zone" do
    event = create_event(timezone: "America/Denver")
    race = create_race(event:, category: nil, age_group: "Masters 35+")
    register(race:, bib: "101")
    register(race:, bib: "102")
    t = Time.utc(2026, 10, 18, 16, 42, 9).to_i * 1000 # 10:42:09 in Denver
    capture = record_capture(device: create_device(event:), seq: 1, at_ms: t, bib: "101", id: "c1")
    lines = {
      { "kind" => "void_capture", "capture_id" => capture.id } => "Void crossing 10:42:09 (bib 101)",
      { "kind" => "assign_bib", "capture_id" => capture.id, "bib" => "102" } => "Bib 101 → 102 for crossing 10:42:09",
      { "kind" => "insert_capture", "bib" => "101", "at_ms" => t } => "Insert crossing 10:42:09 for bib 101",
      { "kind" => "pull", "bib" => "101", "at_ms" => t } => "Pull bib 101 at 10:42:09",
      { "kind" => "flag_finish", "bib" => "101", "capture_id" => capture.id } => "Finish bib 101 at 10:42:09",
      { "kind" => "dnf", "bib" => "101" } => "DNF bib 101",
      { "kind" => "set_lap_count", "race_id" => race.id, "laps" => 3 } => "Lap count 3 for Masters 35+ Men",
      { "kind" => "set_race_start", "race_id" => race.id, "at_ms" => t } => "Start Masters 35+ Men at 10:42:09"
    }
    lines.each do |attrs, line|
      ruling = Ruling.create!(event:, kind: attrs["kind"], payload: attrs.except("kind"))
      revert = Ruling.create!(event:, kind: "revert", payload: { "ruling_id" => ruling.id })
      describer = RulingDescriber.new(event) # it loads the event's rulings when built
      assert_equal line, describer.describe(ruling)
      assert_equal "Undo: #{line}", describer.describe(revert)
    end
  end
end
