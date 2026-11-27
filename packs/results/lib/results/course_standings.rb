module Results
  # Ranking within one course race: finishers by time from the gun; then riders
  # still out (and pulled riders) by the furthest checkpoint reached, earliest there first.
  module CourseStandings
    UNPLACED = %i[dnf dns dsq].freeze

    module_function

    def rows(racers, course)
      position = course.to_h { [ it.id, it.position ] }
      reached = ->(r) { r.passes.keys.map { position[it] }.max || 0 }
      last_at = ->(r) { r.passes.max_by { |id, _| position[id] }&.last&.at_ms || Float::INFINITY }
      finished = racers.select { it.status == :finished }.sort_by { [ it.finish.at_ms, it.finish.ref, it.entrant.bib ] }
      out = racers.select { %i[racing pulled].include?(it.status) }
                  .sort_by { [ it.status == :pulled ? 1 : 0, -reached.(it), last_at.(it), it.entrant.bib ] }
      unplaced = UNPLACED.flat_map { |s| racers.select { it.status == s }.sort_by { it.entrant.bib } }
      leader = finished.first
      (finished + out).each_with_index.map { |r, i| row(r, i + 1, leader, course) } + unplaced.map { row(it, nil, nil, course) }
    end

    def row(racer, place, leader, course)
      last = racer.finish || racer.passes.values.max_by(&:at_ms)
      elapsed = (last.at_ms - racer.race_start if place && last && racer.race_start)
      gap = (Gap.new(laps_down: 0, ms: elapsed - (leader.finish.at_ms - leader.race_start)) if racer.finish && leader && !leader.equal?(racer))
      RacerResult.new(place:, bib: racer.entrant.bib, name: racer.entrant.name, status: racer.status, laps: racer.passes.size,
                      elapsed_ms: elapsed, gap:, lap_times_ms: [], crossings: crossing_views(racer), lap_positions: [],
                      pull_at_ms: racer.pull_at, finish_ref: racer.finish&.ref, splits: splits(racer, course))
    end

    def splits(racer, course)
      previous = racer.race_start
      course.map do |point|
        c = racer.passes[point.id]
        split = Split.new(checkpoint_id: point.id, at_ms: c&.at_ms, elapsed_ms: c && racer.race_start && c.at_ms - racer.race_start,
                          segment_ms: c && previous && c.at_ms - previous, ref: c&.ref, inserted: c&.inserted || false)
        previous = c.at_ms if c
        split
      end
    end

    def crossing_views(racer)
      counted = racer.passes.values.to_h { [ it.ref, it ] }
      views = racer.seen.map do |c|
        kind = if counted.key?(c.ref) then c.checkpoint_id.nil? ? :finish : :split
        elsif racer.race_start.nil? || c.at_ms < racer.race_start then :before_start
        elsif racer.pull_at && c.at_ms > racer.pull_at then :after_pull
        elsif racer.finish && c.at_ms > racer.finish.at_ms then :after_finish
        else :duplicate
        end
        CrossingView.new(ref: c.ref, at_ms: c.at_ms, inserted: c.inserted, kind:, lap: nil, lap_ms: nil, checkpoint_id: c.checkpoint_id)
      end
      views += racer.dropped.map do
        CrossingView.new(ref: it.ref, at_ms: it.at_ms, inserted: it.inserted, kind: :duplicate, lap: nil, lap_ms: nil, checkpoint_id: it.checkpoint_id)
      end
      views.sort_by { [ it.at_ms, it.ref ] }
    end
  end
end
