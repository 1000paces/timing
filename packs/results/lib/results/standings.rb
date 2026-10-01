module Results
  # Spec §4.3: ranking within one race.
  module Standings
    UNPLACED = %i[dnf dns dsq].freeze

    module_function

    def rows(riders)
      running = riders.select { %i[finished racing].include?(it.status) }
                      .sort_by { [-it.counted.size, it.counted.last&.at_ms || Float::INFINITY, it.counted.last&.ref || "", it.entrant.bib] }
      pulled = riders.select { it.status == :pulled }.sort_by { [-it.counted.size, it.pull_at, it.entrant.bib] }
      unplaced = UNPLACED.flat_map { |s| riders.select { it.status == s }.sort_by { it.entrant.bib } }
      placed = running + pulled
      leader = placed.first
      placed.each_with_index.map { |r, i| row(r, i + 1, leader) } + unplaced.map { row(it, nil, nil) }
    end

    def row(rider, place, leader)
      last = rider.counted.last
      elapsed = (last.at_ms - rider.race_start if place && last && rider.race_start)
      RiderResult.new(place:, bib: rider.entrant.bib, name: rider.entrant.name, status: rider.status, laps: rider.counted.size,
                      elapsed_ms: elapsed, gap: gap(rider, elapsed, place, leader), lap_times_ms: lap_times(rider))
    end

    def gap(rider, elapsed, place, leader)
      return nil if place.nil? || place == 1 || elapsed.nil? || rider.status == :pulled || leader.counted.empty?
      lead_laps = leader.counted.size
      return Gap.new(laps_down: lead_laps - rider.counted.size, ms: nil) if rider.counted.size != lead_laps
      Gap.new(laps_down: 0, ms: elapsed - (leader.counted.last.at_ms - leader.race_start))
    end

    def lap_times(rider)
      return [] unless rider.race_start
      ([rider.race_start] + rider.counted.map(&:at_ms)).each_cons(2).map { |a, b| b - a }
    end
  end
end
