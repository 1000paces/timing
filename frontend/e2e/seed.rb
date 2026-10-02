# Seeds the Playwright database (see bin/e2e-server).
Official.create!(name: "E2E Chief", role: "chief", pin: "2468")
Official.create!(name: "E2E Timer", role: "timer", pin: "1357")
Official.create!(name: "E2E Admin", role: "admin", pin: "9753")
event = RaceSimulator::Demo.create!(riders_per_race: 4, name: "E2E CX")
puts "Seeded #{event.name} (#{event.id})"
capture = RaceSimulator::Demo.create!(riders_per_race: 1, name: "E2E Capture")
masters35 = capture.races.find { it.name == "Masters 35+ Men" }
RaceSimulator::Writer.new(event: capture).start_races([masters35], at_ms: Clock.now_ms)
puts "Seeded #{capture.name} (#{capture.id})"
