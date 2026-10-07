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
      positions = lap_positions(racers)
      placed.each_with_index.map { |r, i| row(r, i + 1, leader, positions) } + unplaced.map { row(it, nil, nil, positions) }
    end

    def row(racer, place, leader, positions)
      last = racer.counted.last
      elapsed = (last.at_ms - racer.race_start if place && last && racer.race_start)
      RacerResult.new(place:, bib: racer.entrant.bib, name: racer.entrant.name, status: racer.status, laps: racer.counted.size,
                      elapsed_ms: elapsed, gap: gap(racer, elapsed, place, leader), lap_times_ms: lap_times(racer),
                      crossings: crossing_views(racer), lap_positions: positions.fetch(racer.entrant.bib, []),
                      pull_at_ms: racer.pull_at, finish_ref: racer.finish&.ref)
    end

    # bib => position at the end of each counted lap: for lap N, the racers with
    # at least N counted crossings, ranked by that crossing's time (then ref).
    def lap_positions(racers)
      positions = Hash.new { |h, k| h[k] = [] }
      depth = racers.map { it.counted.size }.max || 0
      (0...depth).each do |n|
        racers.select { it.counted.size > n }.sort_by { [it.counted[n].at_ms, it.counted[n].ref] }
              .each_with_index { |r, i| positions[r.entrant.bib] << i + 1 }
      end
      positions
    end

    # Every crossing the engine saw for this racer, in time order, with what it counted as.
    def crossing_views(racer)
      counted = racer.counted.each_with_index.to_h { |c, i| [c.ref, i] }
      views = racer.seen.map do |c|
        if (i = counted[c.ref])
          previous = i.zero? ? racer.race_start : racer.counted[i - 1].at_ms
          kind = racer.finish&.ref == c.ref ? :finish : :lap
          CrossingView.new(ref: c.ref, at_ms: c.at_ms, inserted: c.inserted, kind:, lap: i + 1, lap_ms: c.at_ms - previous)
        else
          CrossingView.new(ref: c.ref, at_ms: c.at_ms, inserted: c.inserted, kind: ignored_kind(racer, c), lap: nil, lap_ms: nil)
        end
      end
      views += racer.dropped.map { CrossingView.new(ref: it.ref, at_ms: it.at_ms, inserted: it.inserted, kind: :duplicate, lap: nil, lap_ms: nil) }
      views.sort_by { [it.at_ms, it.ref] }
    end

    def ignored_kind(racer, crossing)
      return :before_start if racer.race_start.nil? || crossing.at_ms < racer.race_start
      return :after_pull if racer.pull_at && crossing.at_ms > racer.pull_at
      :after_finish
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
