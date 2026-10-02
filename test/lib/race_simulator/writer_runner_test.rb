require "test_helper"

class RaceSimulator::WriterRunnerTest < ActiveSupport::TestCase
  setup do
    @event = RaceSimulator::Demo.create!(riders_per_race: 3)
    @group = @event.start_groups.first
  end

  test "demo event has one timed start group with three races at 30 s offsets" do
    assert_equal({ "type" => "timed", "target_duration_ms" => 1_500_000 }, @group.finish_rule)
    assert_equal [0, 30_000, 60_000], @group.races.order(:start_offset_ms).pluck(:start_offset_ms)
    assert_equal %w[101 102 103 201 202 203 301 302 303], @event.registrations.order(:bib).pluck(:bib)
  end

  test "writer and runner record the gun, lap count, and taps — untagged ones without a bib" do
    truths = RaceSimulator::Generator.new(races: RaceSimulator.specs_for(@group), laps: 3, seed: 3, untagged_rate: 1.0).call
    writer = RaceSimulator::Writer.new(event: @event)
    writer.fire_gun(@group, at_ms: 1_000_000)
    writer.set_lap_count(@group, 3)
    slept = []
    RaceSimulator::Runner.new(writer:, gun_at_ms: 1_000_000, truths:, speed: 1000, sleeper: ->(s) { slept << s }).call

    taps = RaceSimulator::Runner.taps(truths)
    captures = Capture.where(event: @event).order(:device_seq)
    assert_equal taps.size, captures.count
    assert_equal taps.map { 1_000_000 + it.at_ms }, captures.pluck(:captured_at_ms)
    assert_equal truths.sum { it.untagged.size }, captures.where(bib: nil).count
    assert_equal (1..taps.size).to_a, captures.pluck(:device_seq)
    assert slept.any?
    assert_equal %w[set_group_start set_lap_count], Ruling.where(event: @event).order(:created_at_ms, :id).pluck(:kind)
  end
end
