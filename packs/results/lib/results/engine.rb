module Results
  class Engine
    def initialize(input)
      @input = input
    end

    def call
      resolved = Resolver.new(@input).call
      scored = cohorts.flat_map { score(it, resolved) }
      races = scored.flat_map(&:race_results).map { it.with(publication: Publication.for(it.race_id, resolved.rulings, it.digest)) }
      suggestions = Anomalies.new(@input, resolved, scored).call
      Output.new(races:, suggestions:, unassigned: resolved.unassigned)
    end

    private

    # A race that started after its cohort's finish opened was never on course
    # with that leader, so it is scored on its own (and so on, recursively).
    def score(cohort, resolved)
      scored = CohortScorer.new(@input, cohort, resolved).call
      open_at = scored.finish_open_at
      return [ scored ] unless open_at
      starts = scored.race_results.to_h { [ it.race_id, it.start_at_ms ] }
      late = cohort.select { (start = starts[it.id]) && start > open_at }
      return [ scored ] if late.empty?
      score(cohort - late, resolved) + late.flat_map { score([ it ], resolved) }
    end

    # Finish-with-leader races sharing a scheduled start finish together; every
    # other race (or one with no scheduled start) is a cohort of its own.
    def cohorts
      races = @input.races.uniq(&:id).sort_by(&:id)
      together, alone = races.partition { it.finish_with_leader && it.scheduled_at_ms }
      (together.group_by(&:scheduled_at_ms).values + alone.map { [ it ] }).sort_by { |c| [ c.first.scheduled_at_ms || Float::INFINITY, c.first.id ] }
    end
  end
end
