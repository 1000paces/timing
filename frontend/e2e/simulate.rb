# Writes a simulated 3-lap race for "E2E CX" from the GO time the console
# recorded. Some taps have no bib, so the review queue has work to do.
event = Event.find_by!(name: "E2E CX")
group = event.start_groups.first
gun = Ruling.where(event:, kind: "set_group_start").order(:created_at_ms, :id).last&.payload&.fetch("at_ms")
abort "GO has not been pressed" unless gun
truths = RaceSimulator::Generator.new(races: RaceSimulator.specs_for(group), laps: 3,
                                      seed: Integer(ENV.fetch("SEED", "7")), untagged_rate: 0.5).call
untagged = truths.sum { it.untagged.size }
abort "seed produced no bib-less taps; pick another SEED" if untagged.zero?
RaceSimulator::Runner.new(writer: RaceSimulator::Writer.new(event:), gun_at_ms: gun, truths:).call
puts "Wrote #{RaceSimulator::Runner.taps(truths).size} taps (#{untagged} without a bib); " \
     "GO rulings: #{Ruling.where(event:, kind: 'set_group_start').count}"
