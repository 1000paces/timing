# Seeds the Playwright database (see bin/e2e-server).
Official.create!(name: "E2E Chief", role: "chief", pin: "2468")
Official.create!(name: "E2E Timer", role: "timer", pin: "1357")
Official.create!(name: "E2E Admin", role: "admin", pin: "9753")
event = RaceSimulator::Demo.create!(racers_per_race: 4, name: "E2E CX")
puts "Seeded #{event.name} (#{event.id})"
# Masters 35+ Men started 10 minutes ago with 60 s laps (a tablet's captures):
# 102 and 103 have 3 laps, 101 has 2, so 101 typed now is a long lap.
capture = RaceSimulator::Demo.create!(racers_per_race: 3, name: "E2E Capture")
masters35 = capture.races.find { it.name == "Masters 35+ Men" }
writer = RaceSimulator::Writer.new(event: capture, device_name: "Tablet")
start = Clock.now_ms - 600_000
writer.start_races([ masters35 ], at_ms: start)
{ "101" => 2, "102" => 3, "103" => 3 }.each { |bib, laps| (1..laps).each { writer.capture(at_ms: start + it * 60_000, bib:) } }
puts "Seeded #{capture.name} (#{capture.id})"

# Registration: two races, Cat 3 Men with its own bib range, an event-wide range for the rest.
registration = Event.create!(name: "E2E Registration", date: Date.new(2026, 10, 18), discipline: "cyclocross", bib_from: 1, bib_to: 99)
six_pm = Time.zone.local(2026, 10, 18, 18).to_i * 1000
Race.create!(event: registration, name_override: "Women Open", gender: "women", scheduled_at_ms: six_pm)
Race.create!(event: registration, category: "Cat 3", gender: "men", scheduled_at_ms: six_pm, bib_from: 100, bib_to: 199)
puts "Seeded #{registration.name} (#{registration.id})"

# Officiating: Masters 35+ Men started 10 minutes ago; 101 has a duplicate tap.
officiating = RaceSimulator::Demo.create!(racers_per_race: 3, name: "E2E Officiating")
m35 = officiating.races.find { it.name == "Masters 35+ Men" }
tablet = RaceSimulator::Writer.new(event: officiating, device_name: "Finish phone")
go = Clock.now_ms - 600_000
tablet.start_races([ m35 ], at_ms: go)
{ "101" => [ 60, 120, 123, 180 ], "102" => [ 65, 130 ], "103" => [ 70 ] }.each do |bib, secs|
  secs.each { tablet.capture(at_ms: go + it * 1000, bib:) }
end
puts "Seeded #{officiating.name} (#{officiating.id})"
