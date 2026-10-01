require "test_helper"

class GoldenTest < Minitest::Test
  include ResultsTestHelpers

  Dir[File.expand_path("fixtures/races/*.yml", __dir__)].sort.each do |path|
    name = File.basename(path, ".yml")
    define_method("test_#{name.tr('-', '_')}") do
      input, expected = Results::Fixture.load(path)
      out = Results.compute(input)
      expected.fetch("races").each do |race_id, rows|
        race = out.races.find { it.race_id == race_id }
        assert race, "#{name}: missing race #{race_id}"
        assert_equal normalize_rows(rows), compact_rows(race.rows), "#{name}: race #{race_id}"
      end
      if expected.key?("suggestions")
        assert_equal expected["suggestions"].sort, out.suggestions.map(&:key), "#{name}: suggestions"
      end
    end
  end
end
