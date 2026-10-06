module Mutations
  class AssignBibs < BaseMutation
    description "Give racers without a bib the lowest free number in their race's range (or the event's); existing bibs never change"
    argument :event_id, ID

    field :assigned, [Types::BibAssignmentType], null: false
    field :unfilled, [String], null: false

    def resolve(event_id:)
      require_official!("chief")
      result = BibAssigner.call(Event.find(event_id))
      assigned = result.assigned.map { |reg, bib| { bib:, name: reg.racer.full_name, race_name: reg.race.name } }
      { assigned:, unfilled: result.unfilled, errors: [] }
    end
  end
end
