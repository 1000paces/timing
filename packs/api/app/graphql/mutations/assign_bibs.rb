module Mutations
  class AssignBibs < BaseMutation
    description "Give racers without a bib the lowest free number in their race's range (or the event's); existing bibs never change"
    argument :event_id, ID
    argument :race_id, ID, required: false, description: "Only this race; otherwise every race in the event"

    field :assigned, [ Types::BibAssignmentType ], null: false
    field :unfilled, [ String ], null: false

    def resolve(event_id:, race_id: nil)
      require_official!("chief")
      event = Event.find(event_id)
      result = BibAssigner.call(event, races: race_id && [ event.races.find(race_id) ])
      assigned = result.assigned.map { |reg, bib| { bib:, name: reg.racer.full_name, race_name: reg.race.name } }
      { assigned:, unfilled: result.unfilled, errors: [] }
    end
  end
end
