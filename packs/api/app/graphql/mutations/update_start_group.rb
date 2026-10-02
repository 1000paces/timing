module Mutations
  class UpdateStartGroup < BaseMutation
    argument :id, ID
    argument :name, String, required: false
    argument :finish_rule, GraphQL::Types::JSON, required: false
    argument :scheduled_at_ms, Types::Millis, required: false

    field :start_group, Types::StartGroupType

    def resolve(id:, **attrs)
      require_official!("admin")
      group = StartGroup.find(id)
      group.assign_attributes(attrs)
      persist(group, :start_group)
    end
  end
end
