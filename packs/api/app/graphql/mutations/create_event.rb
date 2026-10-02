module Mutations
  class CreateEvent < BaseMutation
    argument :name, String
    argument :date, GraphQL::Types::ISO8601Date
    argument :venue, String, required: false
    argument :timezone, String, required: false
    argument :age_rule, String, required: false

    field :event, Types::EventType

    def resolve(**attrs)
      require_official!("admin")
      persist(Event.new(attrs.compact), :event)
    end
  end
end
