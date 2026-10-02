module Types
  class MutationType < BaseObject
    field :create_event, mutation: Mutations::CreateEvent
    field :create_category, mutation: Mutations::CreateCategory
    field :create_start_group, mutation: Mutations::CreateStartGroup
    field :update_start_group, mutation: Mutations::UpdateStartGroup
    field :create_race, mutation: Mutations::CreateRace
    field :register_rider, mutation: Mutations::RegisterRider
    field :create_official, mutation: Mutations::CreateOfficial
    field :import_registrations, mutation: Mutations::ImportRegistrations
  end
end
