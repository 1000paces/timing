require "yaml"

module RaceSimulator
  # Replays a course event (point to point / single loop) from a dataset of
  # elapsed times at each checkpoint: one phone per checkpoint and one at the finish.
  module CourseReplay
    Rider = Data.define(:bib, :elapsed_s) # elapsed_s: seconds per point, nil for a missed tap; short = stopped
    RaceData = Data.define(:name, :riders) # not Race: that would hide the Race model in this module
    Dataset = Data.define(:event, :gun, :checkpoints, :finish, :races)

    module_function

    def load(name)
      yaml = YAML.safe_load_file(Pathname(__dir__).join("data", name, "course.yml"))
      races = yaml.fetch("races").map do |r|
        RaceData.new(name: r.fetch("name"), riders: r.fetch("riders").map { |bib, times| Rider.new(bib: bib.to_s, elapsed_s: times.map { seconds(it) }) })
      end
      Dataset.new(event: yaml.fetch("event").transform_keys(&:to_sym), gun: yaml.fetch("gun"), checkpoints: yaml.fetch("checkpoints"),
                  finish: yaml.fetch("finish", {}), races:)
    end

    # "1:02:00" → 3720; "-" → nil.
    def seconds(text) = text == "-" ? nil : text.split(":").map(&:to_i).inject { |a, b| a * 60 + b }

    def setup!(dataset)
      details = dataset.event
      zone = Time.find_zone!(details[:timezone])
      clock = ->(hhmm) { hhmm && zone.parse("#{details[:date]} #{hhmm}").to_i * 1000 }
      event = Event.create!(name: Replay.unused_name(details[:name]), date: Date.parse(details[:date]), location: details[:location],
                            discipline: details[:discipline], timezone: details[:timezone], race_format: "course",
                            finish_distance_km: dataset.finish["km"], finish_cutoff_at_ms: clock.(dataset.finish["cutoff"]))
      dataset.checkpoints.each.with_index(1) do |c, position|
        event.checkpoints.create!(position:, name: c.fetch("name"), distance_km: c["km"], cutoff_at_ms: clock.(c["cutoff"]))
      end
      dataset.races.each do |r|
        race = Race.create!(event:, name_override: r.name, gender: "open", scheduled_at_ms: clock.(dataset.gun))
        r.riders.each do |rider|
          racer = Racer.create!(first_name: Replay::FIRST["F"].sample(random: Random.new(rider.bib.to_i)),
                                last_name: Replay::LAST.sample(random: Random.new(rider.bib.to_i)), gender: "F",
                                birth_date: Date.new(1990, 1, 1))
          Registration.create!(race:, racer:, bib: rider.bib)
        end
      end
      event
    end

    def run(event:, dataset:, out: $stdout)
      points = event.checkpoints.to_a + [ nil ]
      writers = points.map { Writer.new(event:, device_name: "#{it&.name || 'Finish'} phone", checkpoint: it) }
      event.races.each do |race|
        gun = race.scheduled_at_ms
        writers.last.start_races([ race ], at_ms: gun)
        dataset.races.find { it.name == race.name }.riders.each do |rider|
          rider.elapsed_s.each_with_index { |s, i| writers[i].capture(at_ms: gun + s * 1000, bib: rider.bib) if s }
        end
      end
      out.puts "#{event.name} (#{event.id}): replayed #{dataset.races.sum { it.riders.size }} riders over #{points.size} timing points"
    end
  end
end
