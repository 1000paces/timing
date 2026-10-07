require "test_helper"

class RaceSimulator::WriterRunnerTest < ActiveSupport::TestCase
  setup do
    @event = RaceSimulator::Demo.create!(racers_per_race: 3)
  end

  test "demo event is a cyclocross event with three races scheduled together" do
    assert_equal "cyclocross", @event.discipline
    assert_equal %w[Masters\ 35+\ Men Masters\ 50+\ Men Women\ Open], @event.races.map(&:name).sort
    assert_equal 1, @event.races.map(&:scheduled_at_ms).uniq.size
    assert_equal %w[101 102 103 201 202 203 301 302 303], @event.registrations.order(:bib).pluck(:bib)
  end

  test "writer and runner record the gun, lap count, and taps — untagged ones without a bib" do
    truths = RaceSimulator::Generator.new(races: RaceSimulator.specs_for(@event.races), laps: 3, seed: 3, untagged_rate: 1.0).call
    writer = RaceSimulator::Writer.new(event: @event)
    writer.start_races(@event.races, at_ms: 1_000_000)
    writer.set_lap_count(@event.races.first, 3)
    slept = []
    RaceSimulator::Runner.new(writer:, gun_at_ms: 1_000_000, truths:, speed: 1000, sleeper: ->(s) { slept << s }).call

    taps = RaceSimulator::Runner.taps(truths)
    captures = Capture.where(event: @event).order(:device_seq)
    assert_equal taps.size, captures.count
    assert_equal taps.map { 1_000_000 + it.at_ms }, captures.pluck(:captured_at_ms)
    assert_equal truths.sum { it.untagged.size }, captures.where(bib: nil).count
    assert_equal (1..taps.size).to_a, captures.pluck(:device_seq)
    assert slept.any?
    assert_equal %w[set_lap_count set_race_start set_race_start set_race_start], Ruling.where(event: @event).pluck(:kind).sort
  end
end
