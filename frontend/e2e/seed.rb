# Seeds the Playwright database (see bin/e2e-server).
Official.create!(name: "E2E Chief", role: "chief", pin: "2468")
Official.create!(name: "E2E Timer", role: "timer", pin: "1357")
Official.create!(name: "E2E Admin", role: "admin", pin: "9753")
event = RaceSimulator::Demo.create!(riders_per_race: 4, name: "E2E CX")
puts "Seeded #{event.name} (#{event.id})"
# Masters 35+ Men started 10 minutes ago with 60 s laps (a tablet's captures):
# 102 and 103 have 3 laps, 101 has 2, so 101 typed now is a long lap.
capture = RaceSimulator::Demo.create!(riders_per_race: 3, name: "E2E Capture")
masters35 = capture.races.find { it.name == "Masters 35+ Men" }
writer = RaceSimulator::Writer.new(event: capture, device_name: "Tablet")
start = Clock.now_ms - 600_000
writer.start_races([masters35], at_ms: start)
{ "101" => 2, "102" => 3, "103" => 3 }.each { |bib, laps| (1..laps).each { writer.capture(at_ms: start + it * 60_000, bib:) } }
puts "Seeded #{capture.name} (#{capture.id})"
