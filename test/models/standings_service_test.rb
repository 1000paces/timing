require "test_helper"

class StandingsServiceTest < ActiveSupport::TestCase
  setup do
    StandingsService::LAST_GOOD.clear
    @event = create_event
    race = create_race(event: @event)
    register(race:, bib: "1")
    rule(event: @event, kind: "set_group_start", start_group_id: race.start_group_id, at_ms: 0)
    record_capture(device: create_device(event: @event), seq: 1, at_ms: 100_000, bib: "1")
  end

  test "reports fresh standings" do
    report = StandingsService.report(@event, now_ms: 500_000)
    refute report.stale
    assert_nil report.error
    assert_equal 500_000, report.computed_at_ms
    assert_equal ["1"], report.output.races.first.rows.map(&:bib)
  end

  # Review Focus 3
  test "falls back to the last good standings when computing fails" do
    StandingsService.report(@event, now_ms: 500_000)
    broken = ->(*, **) { raise ArgumentError, "comparison of Integer with nil failed" }
    report = StandingsService.report(@event, now_ms: 600_000, compute: broken)
    assert report.stale
    assert_equal "ArgumentError: comparison of Integer with nil failed", report.error
    assert_equal 500_000, report.computed_at_ms
    assert_equal ["1"], report.output.races.first.rows.map(&:bib)
  end

  test "with no previous result the fallback is empty" do
    other = create_event(name: "Other")
    report = StandingsService.report(other, compute: ->(*, **) { raise "boom" })
    assert report.stale
    assert_empty report.output.races
  end
end
