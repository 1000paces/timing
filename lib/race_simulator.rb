# Writes realistic races straight into the hub, as if a tablet were tapping.
module RaceSimulator
  RaceSpec = Data.define(:race_id, :offset_ms, :bibs)
  RacerTruth = Data.define(:bib, :race_id, :crossings_ms, :untagged)

  def self.specs_for(races)
    races.includes(:registrations).order(:id).map do |race|
      RaceSpec.new(race_id: race.id, offset_ms: 0, bibs: race.registrations.map(&:bib).sort)
    end
  end

  def self.run(event:, speed:, seed:, laps:, untagged_rate:, out: $stdout)
    writer = Writer.new(event:)
    gun = Clock.now_ms
    writer.start_races(event.races, at_ms: gun)
    event.races.each { writer.set_lap_count(it, laps) }
    truths = Generator.new(races: specs_for(event.races), laps:, seed:, untagged_rate:).call
    out.puts "Event #{event.id}: gun fired, #{Runner.taps(truths).size} taps to write at #{speed.positive? ? "#{speed}x" : 'once'}"
    Runner.new(writer:, gun_at_ms: gun, truths:, speed:).call
    out.puts "Done. See standings: bin/rails hub:standings EVENT=#{event.id}"
  end
end
