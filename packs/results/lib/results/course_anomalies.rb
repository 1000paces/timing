module Results
  # Problems on course races: a checkpoint skipped, a rider overdue at their
  # next checkpoint, a cutoff missed. Suggestions only, like Anomalies.
  class CourseAnomalies
    OVERDUE_FACTOR = 1.5
    MIN_FIELD = 3

    def initialize(input, courses, dismissed = Set.new)
      @now = input.now_ms
      @courses = courses
      @dismissed = dismissed
    end

    def call = @courses.flat_map { |scored| scored.racers.flat_map { racer_suggestions(it, scored) } }

    private

    def racer_suggestions(racer, scored)
      return [] unless racer.race_start && %i[racing finished].include?(racer.status)
      course = scored.race.course
      return Array(overdue(racer, course, scored)) if racer.passes.empty?
      missed = missed_checkpoints(racer, course, scored)
      return missed + Array(cutoff(racer, course, scored)) if racer.status == :finished
      missed + Array(cutoff(racer, course, scored)) + Array(overdue(racer, course, scored))
    end

    # A checkpoint with no pass while a later checkpoint (or the finish) has one.
    def missed_checkpoints(racer, course, scored)
      course.each_with_index.filter_map do |point, i|
        next if point.id.nil? || racer.passes.key?(point.id)
        after = course[(i + 1)..].find { racer.passes.key?(it.id) } or next
        before = course[0...i].reverse.find { racer.passes.key?(it.id) }
        at = interpolate(racer, before, point, after)
        bib = racer.entrant.bib
        Suggestion.new(key: "missed_checkpoint:#{bib}:#{point.id}", kind: :missed_checkpoint, bib:, race_id: scored.race.id,
                       message: "Bib #{bib} was seen at #{after.name} but not at #{point.name} — missed tap, or cut the course?",
                       fix: { "kind" => "insert_capture", "bib" => bib, "at_ms" => at, "checkpoint_id" => point.id })
      end
    end

    # By distance when all three are known (the start is 0 km), else the midpoint.
    def interpolate(racer, before, point, after)
      from_at = before ? racer.passes[before.id].at_ms : racer.race_start
      from_km = before ? before.distance_km : 0
      to_at = racer.passes[after.id].at_ms
      if from_km && point.distance_km && after.distance_km && after.distance_km > from_km
        (from_at + ((to_at - from_at) * (point.distance_km - from_km) / (after.distance_km - from_km).to_f).round).clamp(from_at..[ from_at, to_at ].max)
      else
        (from_at + to_at) / 2
      end
    end

    # The first checkpoint whose cutoff has passed without the rider, or that they reached late.
    # A finisher reached every point they skipped later, so only a late pass counts for them.
    def cutoff(racer, course, scored)
      point = course.find do |p|
        next false unless p.cutoff_at_ms && !@dismissed.include?("cutoff:#{racer.entrant.bib}:#{p.id || 'finish'}")
        pass = racer.passes[p.id]
        pass ? pass.at_ms > p.cutoff_at_ms : @now > p.cutoff_at_ms && course.drop(p.position).none? { racer.passes.key?(it.id) }
      end
      return nil unless point
      bib = racer.entrant.bib
      Suggestion.new(key: "cutoff:#{bib}:#{point.id || 'finish'}", kind: :cutoff, bib:, race_id: scored.race.id,
                     message: "Bib #{bib} missed the #{point.name} cutoff — pull?",
                     fix: { "kind" => "pull", "bib" => bib, "at_ms" => point.cutoff_at_ms })
    end

    def overdue(racer, course, scored)
      last_point = course.select { racer.passes.key?(it.id) }.max_by(&:position)
      last_at = last_point ? racer.passes[last_point.id].at_ms : racer.race_start
      next_point = course[last_point ? last_point.position : 0] or return nil
      expected = own_pace(racer, last_point, next_point) || field(scored.racers, last_point, next_point) || field(everyone, last_point, next_point)
      return nil unless expected && @now > last_at + (expected * OVERDUE_FACTOR).round
      bib = racer.entrant.bib
      key = "overdue:#{bib}:#{(last_point && racer.passes[last_point.id].ref) || 'start'}"
      unless last_point
        return Suggestion.new(key:, kind: :overdue, bib:, race_id: scored.race.id,
                              message: "Bib #{bib} hasn't been seen since the start — never started? Mark DNS",
                              fix: { "kind" => "dns", "bib" => bib })
      end
      Suggestion.new(key:, kind: :overdue, bib:, race_id: scored.race.id,
                     message: "Bib #{bib} is overdue at #{next_point.name}: last seen at #{last_point.name} #{fmt(@now - last_at)} ago, " \
                              "expected about #{fmt(expected)} — stopped? Mark DNF",
                     fix: { "kind" => "dnf", "bib" => bib })
    end

    # Their pace so far (time per km to their last checkpoint) over the next segment's distance.
    def own_pace(racer, last_point, next_point)
      return nil unless last_point&.distance_km&.positive? && next_point.distance_km && next_point.distance_km > last_point.distance_km
      elapsed = racer.passes[last_point.id].at_ms - racer.race_start
      elapsed * (next_point.distance_km - last_point.distance_km) / last_point.distance_km.to_f
    end

    # The median time others in the race took between the same two points.
    # Falls back to every course race in the event when this race has too few.
    def field(racers, from, to)
      times = racers.filter_map do |r|
        to_pass = r.passes[to.id] or next
        from_at = from ? r.passes[from.id]&.at_ms : r.race_start
        to_pass.at_ms - from_at if from_at
      end
      times.size >= MIN_FIELD ? Anomalies.median(times) : nil
    end

    def everyone = @courses.flat_map(&:racers)

    def fmt(ms)
      minutes = (ms / 60_000.0).round
      format("%d:%02d", minutes / 60, minutes % 60)
    end
  end
end
