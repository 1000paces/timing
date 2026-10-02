require "test_helper"

# Spec §10 (simulator-driven): a CX start group with three waves is timed with
# some bib-less taps; officials fix them from the review queue and publish. The
# result must equal what perfect timing would have produced.
class RaceDayTest < ActionDispatch::IntegrationTest
  STANDINGS = <<~GQL
    query($id: ID!) {
      standings(eventId: $id) {
        races { race { id } publication rows { place bib status laps elapsedMs } }
        suggestions { key kind }
      }
    }
  GQL

  setup { StandingsService::LAST_GOOD.clear }

  def standings = gql(STANDINGS, id: @event.id).dig("data", "standings")

  def perfect_rows(races, truths, gun)
    rulings = races.flat_map do |race|
      [Results::Ruling.new(id: "start-#{race.id}", kind: "set_race_start", payload: { "race_id" => race.id, "at_ms" => gun }, created_at_ms: 0),
       Results::Ruling.new(id: "laps-#{race.id}", kind: "set_lap_count", payload: { "race_id" => race.id, "laps" => 5 }, created_at_ms: 1)]
    end
    captures = truths.flat_map do |t|
      t.crossings_ms.each_with_index.map do |ms, i|
        Results::Capture.new(id: "#{t.bib}-#{i}", device_id: "d", device_seq: 0, captured_at_ms: gun + ms, clock_offset_ms: 0, bib: t.bib)
      end
    end
    input = ResultsSnapshot.for(@event, now_ms: Clock.now_ms).with(captures:, bib_assignments: [], rulings:)
    Results.compute(input).races.to_h do |race|
      [race.race_id, race.rows.map { [it.place, it.bib, it.status.to_s.upcase, it.laps, it.elapsed_ms] }]
    end
  end

  test "untagged taps fixed from the review queue give the same published standings as perfect timing" do
    sign_in(create_official(role: "chief", pin: "2468"), "2468")
    @event = RaceSimulator::Demo.create!(riders_per_race: 8)
    races = @event.races.to_a

    started = gql("mutation($ids: [ID!]!) { startRaces(raceIds: $ids) { rulings { payload } errors } }", ids: races.map(&:id))
    gun = started.dig("data", "startRaces", "rulings").first.dig("payload", "at_ms")
    assert_empty gql("mutation($id: ID!) { setLapCount(raceId: $id, laps: 5) { errors } }", id: races.first.id)
                   .dig("data", "setLapCount", "errors")

    truths = RaceSimulator::Generator.new(races: RaceSimulator.specs_for(@event.races), laps: 5, seed: 7, untagged_rate: 0.5).call
    untagged = truths.sum { it.untagged.size }
    assert_operator untagged, :>=, 3
    RaceSimulator::Runner.new(writer: RaceSimulator::Writer.new(event: @event), gun_at_ms: gun, truths:).call

    missed = standings["suggestions"].select { it["kind"] == "SUSPECTED_MISSED_CROSSING" }
    assert_equal untagged, missed.size
    missed.each do |suggestion|
      result = gql("mutation($id: ID!, $key: String!) { acceptSuggestion(eventId: $id, key: $key) { errors } }",
                   id: @event.id, key: suggestion["key"])
      assert_empty result.dig("data", "acceptSuggestion", "errors"), suggestion["key"]
    end
    assert_empty standings["suggestions"]

    expected = perfect_rows(races, truths, gun)
    standings["races"].each do |race|
      actual = race["rows"].map { [it["place"], it["bib"], it["status"], it["laps"], it["elapsedMs"]] }
      assert_equal expected.fetch(race.dig("race", "id")), actual
      published = gql("mutation($id: ID!) { publishResults(raceId: $id) { errors } }", id: race.dig("race", "id"))
      assert_empty published.dig("data", "publishResults", "errors")
    end
    assert_equal %w[PUBLISHED], standings["races"].map { it["publication"] }.uniq
  end
end
