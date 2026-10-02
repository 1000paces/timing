module Mutations
  class CreateRace < BaseMutation
    argument :event_id, ID
    argument :category_id, ID
    argument :start_group_id, ID
    argument :start_offset_ms, Types::Millis, required: false

    field :race, Types::RaceType

    def resolve(event_id:, category_id:, start_group_id:, start_offset_ms: 0)
      require_official!("admin")
      persist(Race.new(event: Event.find(event_id), category: Category.find(category_id),
                       start_group: StartGroup.find(start_group_id), start_offset_ms:), :race)
    end
  end
end
