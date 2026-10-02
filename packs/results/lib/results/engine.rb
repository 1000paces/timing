module Results
  class Engine
    def initialize(input)
      @input = input
    end

    def call
      resolved = Resolver.new(@input).call
      scored = cohorts.map { CohortScorer.new(@input, it, resolved).call }
      races = scored.flat_map(&:race_results).map { it.with(publication: Publication.for(it.race_id, resolved.rulings, it.digest)) }
      suggestions = Anomalies.new(@input, resolved, scored).call
      Output.new(races:, suggestions:, unassigned: resolved.unassigned)
    end

    private

    # Finish-with-leader races sharing a scheduled start finish together; every
    # other race (or one with no scheduled start) is a cohort of its own.
    def cohorts
      races = @input.races.uniq(&:id).sort_by(&:id)
      together, alone = races.partition { it.finish_with_leader && it.scheduled_at_ms }
      (together.group_by(&:scheduled_at_ms).values + alone.map { [it] }).sort_by { |c| [c.first.scheduled_at_ms || Float::INFINITY, c.first.id] }
    end
  end
end
