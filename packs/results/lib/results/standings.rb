module Results
  # Spec §4.3: ranking within one race.
  module Standings
    UNPLACED = %i[dnf dns dsq].freeze

    module_function

    def rows(racers)
      running = racers.select { %i[finished racing].include?(it.status) }
                      .sort_by { [-it.counted.size, it.counted.last&.at_ms || Float::INFINITY, it.counted.last&.ref || "", it.entrant.bib] }
      pulled = racers.select { it.status == :pulled }.sort_by { [-it.counted.size, it.pull_at, it.entrant.bib] }
      unplaced = UNPLACED.flat_map { |s| racers.select { it.status == s }.sort_by { it.entrant.bib } }
      placed = running + pulled
      leader = placed.first
      placed.each_with_index.map { |r, i| row(r, i + 1, leader) } + unplaced.map { row(it, nil, nil) }
    end

    def row(racer, place, leader)
      last = racer.counted.last
      elapsed = (last.at_ms - racer.race_start if place && last && racer.race_start)
      RacerResult.new(place:, bib: racer.entrant.bib, name: racer.entrant.name, status: racer.status, laps: racer.counted.size,
                      elapsed_ms: elapsed, gap: gap(racer, elapsed, place, leader), lap_times_ms: lap_times(racer))
    end

    def gap(racer, elapsed, place, leader)
      return nil if place.nil? || place == 1 || elapsed.nil? || racer.status == :pulled || leader.counted.empty?
      lead_laps = leader.counted.size
      return Gap.new(laps_down: lead_laps - racer.counted.size, ms: nil) if racer.counted.size != lead_laps
      Gap.new(laps_down: 0, ms: elapsed - (leader.counted.last.at_ms - leader.race_start))
    end

    def lap_times(racer)
      return [] unless racer.race_start
      ([racer.race_start] + racer.counted.map(&:at_ms)).each_cons(2).map { |a, b| b - a }
    end
  end
end
