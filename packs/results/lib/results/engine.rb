module Results
  class Engine
    def initialize(input)
      @input = input
    end

    def call
      resolved = Resolver.new(@input).call
      digest = LogDigest.compute(@input)
      scored = @input.start_groups.uniq(&:id).sort_by(&:id).map { GroupScorer.new(@input, it, resolved).call }
      races = scored.flat_map(&:race_results).map { it.with(publication: Publication.for(it.race_id, resolved.rulings, digest)) }
      suggestions = Anomalies.new(@input, resolved, scored).call
      Output.new(races:, suggestions:, unassigned: resolved.unassigned, log_digest: digest)
    end
  end
end
