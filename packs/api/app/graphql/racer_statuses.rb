# Racers' official statuses (DNF/DNS/DSQ) from the event's active rulings —
# reverts applied, the latest ruling for a bib wins (as in the results engine).
module RacerStatuses
  KINDS = %w[dnf dns dsq].freeze

  # Active status rulings, oldest first.
  def self.active_rulings(event)
    engine = Ruling.where(event:, kind: KINDS + ["revert"])
                   .map { Results::Ruling.new(id: it.id, kind: it.kind, payload: it.payload, created_at_ms: it.created_at_ms) }
    Results::ActiveRulings.new(engine).all.select { KINDS.include?(it.kind) }
  end

  # bib => "DNF" | "DNS" | "DSQ"
  def self.by_bib(event) = active_rulings(event).to_h { [it.payload["bib"].to_s, it.kind.upcase] }
end
