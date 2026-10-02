require "test_helper"

class RaceSimulator::GeneratorTest < ActiveSupport::TestCase
  RACES = [RaceSimulator::RaceSpec.new(race_id: "a", offset_ms: 0, bibs: (101..110).to_a),
           RaceSimulator::RaceSpec.new(race_id: "b", offset_ms: 30_000, bibs: (201..210).to_a)].freeze

  def generate(**opts) = RaceSimulator::Generator.new(races: RACES, laps: 5, seed: 7, **opts).call

  test "is deterministic for a seed" do
    assert_equal generate, generate
    refute_equal generate, RaceSimulator::Generator.new(races: RACES, laps: 5, seed: 8).call
  end

  test "every rider finishes on their first crossing once the leader completes the laps" do
    truths = generate
    leader_finish = truths.filter_map { it.crossings_ms[4] }.min
    truths.each do |t|
      assert_operator t.crossings_ms.last, :>=, leader_finish
      assert t.crossings_ms[0..-2].all? { it < leader_finish }, "bib #{t.bib} has crossings after its finish"
      assert_equal t.crossings_ms.sort, t.crossings_ms
    end
    assert_equal 5, truths.map { it.crossings_ms.size }.max
  end

  test "untagged taps are never a rider's first or last crossing and are spread out" do
    truths = generate(untagged_rate: 1.0)
    picked = truths.flat_map { |t| t.untagged.map { [t, it] } }
    assert_operator picked.size, :>=, 3
    picked.each { |t, i| assert i.between?(1, t.crossings_ms.size - 2) }
    times = picked.map { |t, i| t.crossings_ms[i] }.sort
    assert times.each_cons(2).all? { |a, b| b - a >= 120_000 }
    assert truths.all? { it.untagged.size <= 1 }
  end
end
