module Results
  # Rulings in chronological order with reverts applied. A revert can itself be
  # reverted, which restores its target.
  class ActiveRulings
    attr_reader :all

    def initialize(rulings)
      sorted = rulings.select { RulingShape.valid?(it) }.uniq(&:id).sort_by { [it.created_at_ms, it.id] }
      cancelled = Set.new
      sorted.reverse_each do |r|
        next if cancelled.include?(r.id)
        cancelled << r.payload["ruling_id"] if r.kind == "revert"
      end
      @all = sorted.reject { cancelled.include?(it.id) || it.kind == "revert" }
    end

    def of(kind) = @all.select { it.kind == kind }

    def latest_by(kind, &key) = of(kind).group_by(&key).transform_values(&:last)
  end
end
