require "csv"
require "yaml"

module RaceSimulator
  module Replay
    # One racer's line of the real results: lap times as the timing system
    # measured them (lap 1 from the moment the wave was armed).
    Result = Data.define(:category, :place, :bib, :laps, :laps_ms)
    # finish_with_leader false: the race finishes on its own lap count, not the wave's.
    RaceStart = Data.define(:name, :start_s, :finish_with_leader)

    # A start wave from the race-day schedule. Its races go off start_s apart
    # and (unless a race says otherwise) finish together on one lap count.
    Wave = Data.define(:gun, :minutes, :arm_s, :flag_out_s, :races) do
      # Races that finish together: the wave's, then each race finishing on its own.
      def cohorts
        together, alone = races.partition(&:finish_with_leader)
        [together, *alone.map { [it] }].reject(&:empty?)
      end

      # The lap count is the wave leader's: the most laps anyone in it rode.
      def lap_count(results) = results.map(&:laps).max
    end

    # The committed results and wave layout for one real event, from
    # lib/race_simulator/data/<name>/ (results.csv, and waves.yml with the event details).
    Dataset = Data.define(:event, :waves, :results) do
      def self.load(name)
        dir = Pathname(__dir__).join("../data", name)
        yaml = YAML.safe_load_file(dir.join("waves.yml"))
        waves = yaml.fetch("waves").map do |w|
          Wave.new(gun: w.fetch("gun"), minutes: w.fetch("minutes"), arm_s: w.fetch("arm_s"), flag_out_s: w["flag_out_s"],
                   races: w.fetch("races").map { RaceStart.new(name: it.fetch("name"), start_s: it.fetch("start_s"), finish_with_leader: it.fetch("finish_with_leader", true)) })
        end
        results = CSV.read(dir.join("results.csv"), headers: true).map do |row|
          laps = Integer(row["laps"])
          Result.new(category: row["category"], place: Integer(row["place"]), bib: row["bib"], laps:,
                     laps_ms: (1..laps).map { parse_ms(row["lap#{it}"]) })
        end
        new(event: yaml.fetch("event").transform_keys(&:to_sym), waves:, results:)
      end

      # "07:08.96" (m:ss.hh) or "00:09:21" (h:mm:ss) to milliseconds.
      def self.parse_ms(text)
        parts = text.split(":")
        seconds = parts.size == 3 ? parts[0].to_i * 3600 + parts[1].to_i * 60 + parts[2].to_f : parts[0].to_i * 60 + parts[1].to_f
        (seconds * 1000).round
      end

      def races = waves.flat_map(&:races)
      def wave_of(name) = waves.find { |w| w.races.any? { it.name == name } }
      def results_for(names) = results.select { names.include?(it.category) }
    end
  end
end
