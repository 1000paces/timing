require "test_helper"

# Records reach the hub in any order and may arrive twice; results must not change.
class OrderIndependenceTest < Minitest::Test
  Dir[File.expand_path("fixtures/races/*.yml", __dir__)].sort.each do |path|
    define_method("test_order_independent_#{File.basename(path, '.yml').tr('-', '_')}") do
      input, = Results::Fixture.load(path)
      baseline = Results.compute(input)
      rng = Random.new(42)
      20.times { assert_equal baseline, Results.compute(scramble(input, rng)) }
    end
  end

  private

  def scramble(input, rng)
    with_dups = ->(list) { (list + list.select { rng.rand < 0.3 }).shuffle(random: rng) }
    input.with(races: input.races.shuffle(random: rng),
               entrants: input.entrants.shuffle(random: rng), captures: with_dups.(input.captures),
               bib_assignments: with_dups.(input.bib_assignments), rulings: with_dups.(input.rulings))
  end
end
