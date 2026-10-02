# Seeds the Playwright database (see bin/e2e-server).
Official.create!(name: "E2E Chief", role: "chief", pin: "2468")
Official.create!(name: "E2E Timer", role: "timer", pin: "1357")
event = RaceSimulator::Demo.create!(riders_per_race: 4, name: "E2E CX")
puts "Seeded #{event.name} (#{event.id})"
