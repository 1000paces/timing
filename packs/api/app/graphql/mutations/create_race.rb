module Mutations
  class CreateRace < BaseMutation
    argument :event_id, ID
    argument :category_id, ID
    argument :start_group_id, ID

    field :race, Types::RaceType

    def resolve(event_id:, category_id:, start_group_id:)
      require_official!("admin")
      persist(Race.new(event: Event.find(event_id), category: Category.find(category_id),
                       start_group: StartGroup.find(start_group_id)), :race)
    end
  end
end
