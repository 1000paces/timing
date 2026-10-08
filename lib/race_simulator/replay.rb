module RaceSimulator
  # Replays a real event's published results through the hub: the event, its
  # races and racers (real bibs, made-up names), then every crossing as a
  # finish-line phone would have recorded it. See Replay::Check for how the
  # hub's results are compared with the real ones.
  module Replay
    FIRST = { "M" => %w[Aaron Ben Caleb Dmitri Elliot Felix Gabe Hugo Isaac Jonah Kenji Luis Marco Nico Owen Pavel Quinn Rafael Sam Theo Uri Victor Wes Xavi Yusuf Zane],
              "F" => %w[Ada Bea Cleo Dana Edie Flora Greta Hazel Iris June Kira Lena Maya Nora Opal Pia Rosa Sadie Tess Una Vera Wren Yara Zoe] }.freeze
    LAST = %w[Abbott Becker Castillo Dunn Ellis Fischer Garza Holt Ibarra Jensen Kowalski Lindqvist Moreau Nakamura Okafor Petrov
              Quintero Rasmussen Sato Tran Underwood Varga Whitfield Xu Yilmaz Zeller].freeze

    module_function

    def setup!(dataset)
      details = dataset.event
      zone = Time.find_zone!(details[:timezone])
      date = Date.parse(details[:date])
      event = Event.create!(name: unused_name(details[:name]), date:, location: details[:location], discipline: details[:discipline],
                            timezone: details[:timezone])
      dataset.waves.each do |wave|
        gun_ms = zone.parse("#{date} #{wave.gun}").to_i * 1000
        wave.races.each do |start|
          ages = age_range(start.name)
          race = Race.create!(event:, name_override: start.name, gender: start.name.match?(/Women|Athenas/) ? "women" : "open",
                              finish_with_leader: start.finish_with_leader ? nil : false,
                              age_min: ages&.min, age_max: ages && ages.max < 99 ? ages.max : nil,
                              scheduled_at_ms: gun_ms, expected_duration_ms: wave.minutes * 60_000)
          dataset.results_for([start.name]).each { register(event:, race:, result: it, ages:) }
        end
      end
      event
    end

    # Starts each race at its gun plus offset, sets the wave's lap count, puts
    # the flag out when the data says it came out, and records every crossing
    # at gun + arming delay + the racer's lap times.
    def run(event:, dataset:, speed: 0, out: $stdout, sleeper: ->(seconds) { sleep(seconds) })
      writer = Writer.new(event:, device_name: "Finish phone")
      steps = timeline(event, dataset)
      out.puts "#{event.name} (#{event.id}): #{steps.count { it[1] == :capture }} crossings in #{dataset.waves.size} waves" \
               "#{speed.positive? ? " at #{speed}x" : ''}"
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      first_at = steps.first&.first
      steps.each do |at_ms, kind, arg|
        if speed.positive?
          wait = (at_ms - first_at) / 1000.0 / speed - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
          sleeper.call(wait) if wait.positive?
        end
        case kind
        when :start then writer.start_races([arg], at_ms:)
        when :laps then writer.set_lap_count(*arg)
        when :flag then Ruling.create!(event:, kind: "flag_out", payload: { "race_id" => arg.id, "at_ms" => at_ms })
        when :capture then writer.capture(at_ms:, bib: arg)
        end
      end
      out.puts "Done. Check against the real results: bin/replay-race --check #{event.id}"
    end

    # [at_ms, kind, arg], in time order (starts and lap counts before crossings).
    def timeline(event, dataset)
      races = event.races.index_by(&:name)
      steps = dataset.waves.flat_map do |wave|
        results = dataset.results_for(wave.races.map(&:name))
        gun_ms = races.fetch(wave.races.first.name).scheduled_at_ms
        lap_counts = wave.cohorts.flat_map { |cohort| [wave.lap_count(dataset.results_for(cohort.map(&:name)))] * cohort.size }
        starts = wave.cohorts.flatten.zip(lap_counts).flat_map do |start, lap_count|
          race = races.fetch(start.name)
          at = gun_ms + start.start_s * 1000
          [[at, :start, race], [at, :laps, [race, lap_count]]]
        end
        crossings = results.flat_map do |result|
          at = gun_ms + wave.arm_s * 1000
          result.laps_ms.map { [at += it, :capture, result.bib] }
        end
        flag = wave.flag_out_s && [[gun_ms + (wave.arm_s + wave.flag_out_s) * 1000, :flag, races.fetch(wave.cohorts.first.first.name)]]
        starts + crossings + Array(flag)
      end
      order = { start: 0, laps: 1, flag: 2, capture: 3 }
      steps.sort_by { |at, kind, arg| [at, order[kind], kind == :capture ? arg : ""] }
    end

    def unused_name(name)
      return name unless Event.exists?(name:)
      (2..).lazy.map { "#{name} (#{it})" }.find { !Event.exists?(name: it) }
    end

    # Racing ages a category name implies: "Masters 50+" → 50..59, "Junior Open 9-10" → 9..10.
    def age_range(name)
      if (m = name.match(/(\d+)-(\d+)/)) then m[1].to_i..m[2].to_i
      elsif (m = name.match(/(\d+)\+/)) then m[1].to_i..(m[1].to_i >= 80 ? 89 : m[1].to_i + 9)
      end
    end

    def register(event:, race:, result:, ages:)
      rng = Random.new(result.bib.to_i)
      gender = race.gender == "women" ? "F" : (rng.rand < 0.15 ? "F" : "M")
      age = ages ? rng.rand(ages) : rng.rand(22..45)
      racing_year = event.date.year + (event.age_next_year ? 1 : 0)
      racer = Racer.create!(first_name: FIRST.fetch(gender).sample(random: rng), last_name: LAST.sample(random: rng), gender:,
                            birth_date: Date.new(racing_year - age, rng.rand(1..12), rng.rand(1..28)))
      Registration.create!(race:, racer:, bib: result.bib)
    end
  end
end
