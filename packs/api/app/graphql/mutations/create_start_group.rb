module Mutations
  class CreateStartGroup < BaseMutation
    argument :event_id, ID
    argument :name, String
    argument :finish_rule, GraphQL::Types::JSON
    argument :scheduled_at_ms, Types::Millis, required: false

    field :start_group, Types::StartGroupType

    def resolve(event_id:, **attrs)
      require_official!("admin")
      persist(Event.find(event_id).start_groups.new(attrs), :start_group)
    end
  end
end
