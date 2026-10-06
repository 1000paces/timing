require "test_helper"

class ResultsSnapshotTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @race = create_race(event: @event)
    register(race: @race, bib: "1", racer: create_racer(first_name: "Ann", last_name: "Lee"))
    register(race: @race, bib: "2")
    @device = create_device(event: @event)
  end

  test "computes standings from stored captures and rulings" do
    rule(event: @event, kind: "set_race_start", race_id: @race.id, at_ms: 0, created_at_ms: 0)
    [[1, "1", 100_000], [2, "2", 110_000], [3, "1", 200_000], [4, nil, 215_000]].each do |seq, bib, at|
      record_capture(device: @device, seq:, at_ms: at, bib:, id: "cap-#{seq}")
    end
    rule(event: @event, kind: "assign_bib", capture_id: "cap-4", bib: "2", created_at_ms: 300_000)
    rule(event: @event, kind: "set_lap_count", race_id: @race.id, laps: 2, created_at_ms: 300_001)

    out = ResultsSnapshot.compute(@event, now_ms: 400_000)
    race = out.races.find { it.race_id == @race.id }
    assert_equal :finish_open, race.state
    assert_equal [[1, "1", "Ann Lee", :finished, 2, 200_000], [2, "2", "Ada Racer", :finished, 2, 215_000]],
                 race.rows.map { [it.place, it.bib, it.name, it.status, it.laps, it.elapsed_ms] }
    assert_empty out.unassigned
  end

  test "payload keys survive a database round trip as strings" do
    rule(event: @event, kind: "pull", bib: "2", at_ms: 50_000)
    input = ResultsSnapshot.for(@event, now_ms: 0)
    assert_equal({ "bib" => "2", "at_ms" => 50_000 }, input.rulings.first.payload)
    assert_equal [Results::RaceDef.new(id: @race.id, scheduled_at_ms: @race.scheduled_at_ms, finish_with_leader: true, expected_laps: nil)],
                 input.races
  end

  test "scopes the snapshot to one event" do
    other = create_event(name: "Other")
    record_capture(device: create_device(event: other), seq: 1, at_ms: 1, bib: "1")
    assert_empty ResultsSnapshot.for(@event, now_ms: 0).captures
  end
end
