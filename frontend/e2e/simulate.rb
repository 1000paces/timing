# Writes a simulated 3-lap race for "E2E CX" from the start times the console
# recorded (races may have started in separate waves). Some taps have no bib,
# so the review queue has work to do.
event = Event.find_by!(name: "E2E CX")
group = event.start_groups.first
starts = StandingsService.report(event).output.races.to_h { [it.race_id, it.start_at_ms] }
abort "not every race has started" if starts.values_at(*group.races.map(&:id)).any?(&:nil?)
gun = starts.values.compact.min
specs = RaceSimulator.specs_for(group).map { it.with(offset_ms: starts.fetch(it.race_id) - gun) }
truths = RaceSimulator::Generator.new(races: specs, laps: 3, seed: Integer(ENV.fetch("SEED", "7")), untagged_rate: 0.5).call
untagged = truths.sum { it.untagged.size }
abort "seed produced no bib-less taps; pick another SEED" if untagged.zero?
RaceSimulator::Runner.new(writer: RaceSimulator::Writer.new(event:), gun_at_ms: gun, truths:).call
puts "Wrote #{RaceSimulator::Runner.taps(truths).size} taps (#{untagged} without a bib); " \
     "set_race_start rulings: #{Ruling.where(event:, kind: 'set_race_start').count}"
