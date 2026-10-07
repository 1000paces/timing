# An event's rulings as officials see them: one readable line each, who made
# it, and whether (and by whom) it has been undone.
class RulingHistory
  def initialize(event)
    @event = event
    @rulings = Ruling.where(event:).order(created_at_ms: :desc, id: :desc).to_a
    engine = @rulings.map { Results::Ruling.new(id: it.id, kind: it.kind, payload: it.payload, created_at_ms: it.created_at_ms) }
    @cancelled = Results::ActiveRulings.new(engine).cancelled_ids
    @describer = RulingDescriber.new(event)
    @names = Official.where(id: @rulings.map(&:official_id).compact.uniq).pluck(:id, :name).to_h
    # target id => the active revert that undid it
    @undone_by = @rulings.select { it.kind == "revert" && !@cancelled.include?(it.id) }.to_h { [it.payload["ruling_id"], it] }
  end

  attr_reader :rulings, :describer

  def entry(ruling)
    undo = @undone_by[ruling.id]
    { id: ruling.id, kind: ruling.kind, description: @describer.describe(ruling), bib: @describer.bib_for(ruling),
      official_name: @names[ruling.official_id], created_at_ms: ruling.created_at_ms,
      undone: @cancelled.include?(ruling.id), undone_by: undo && @names[undo.official_id], undone_at_ms: undo&.created_at_ms }
  end

  def undone?(ruling) = @cancelled.include?(ruling.id)

  def official_name(id) = @names[id]
end
