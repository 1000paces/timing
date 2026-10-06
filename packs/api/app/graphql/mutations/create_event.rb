module Mutations
  class CreateEvent < BaseMutation
    argument :name, String
    argument :date, GraphQL::Types::ISO8601Date
    argument :location, String, required: false
    argument :discipline, String
    argument :sub_discipline, String, required: false
    argument :finish_with_leader, Boolean, required: false, description: "Defaults from the discipline"
    argument :bib_from, Integer, required: false
    argument :bib_to, Integer, required: false
    argument :timezone, String, required: false
    argument :age_rule, String, required: false

    field :event, Types::EventType

    def resolve(**attrs)
      require_official!("admin")
      persist(Event.new(attrs.compact), :event)
    end
  end
end
