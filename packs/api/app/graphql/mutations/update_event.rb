module Mutations
  class UpdateEvent < BaseMutation
    argument :id, ID
    argument :name, String, required: false
    argument :date, GraphQL::Types::ISO8601Date, required: false
    argument :location, String, required: false
    argument :discipline, String, required: false
    argument :sub_discipline, String, required: false
    argument :finish_with_leader, Boolean, required: false
    argument :age_next_year, Boolean, required: false
    argument :bib_from, Integer, required: false
    argument :bib_to, Integer, required: false
    argument :timezone, String, required: false
    argument :race_format, String, required: false

    field :event, Types::EventType

    def resolve(id:, **attrs)
      require_official!("admin")
      event = Event.find(id)
      event.assign_attributes(attrs)
      persist(event, :event)
    end
  end
end
