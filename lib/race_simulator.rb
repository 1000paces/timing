# Writes realistic races straight into the hub, as if a tablet were tapping.
module RaceSimulator
  RaceSpec = Data.define(:race_id, :offset_ms, :bibs)
  RiderTruth = Data.define(:bib, :race_id, :crossings_ms, :untagged)

  def self.specs_for(start_group)
    start_group.races.includes(:registrations).order(:id).map do |race|
      RaceSpec.new(race_id: race.id, offset_ms: 0, bibs: race.registrations.map(&:bib).sort)
    end
  end

  def self.run(event:, speed:, seed:, laps:, untagged_rate:, out: $stdout)
    writer = Writer.new(event:)
    gun = Clock.now_ms
    truths = event.start_groups.order(:id).flat_map do |group|
      writer.fire_gun(group, at_ms: gun)
      writer.set_lap_count(group, laps) if group.finish_rule["type"] == "timed"
      Generator.new(races: specs_for(group), laps:, seed:, untagged_rate:).call
    end
    out.puts "Event #{event.id}: gun fired, #{Runner.taps(truths).size} taps to write at #{speed.positive? ? "#{speed}x" : 'once'}"
    Runner.new(writer:, gun_at_ms: gun, truths:, speed:).call
    out.puts "Done. See standings: bin/rails hub:standings EVENT=#{event.id}"
  end
end
