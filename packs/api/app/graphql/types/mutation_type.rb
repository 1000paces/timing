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
    field :fire_start, mutation: Mutations::FireStart
    field :set_race_start, mutation: Mutations::SetRaceStart
    field :set_lap_count, mutation: Mutations::SetLapCount
    field :record_ruling, mutation: Mutations::RecordRuling
    field :revert_ruling, mutation: Mutations::RevertRuling
    field :accept_suggestion, mutation: Mutations::AcceptSuggestion
    field :dismiss_suggestion, mutation: Mutations::DismissSuggestion
    field :publish_results, mutation: Mutations::PublishResults
    field :start_races, mutation: Mutations::StartRaces
    field :unstart_race, mutation: Mutations::UnstartRace
    field :create_pairing_token, mutation: Mutations::CreatePairingToken
    field :revoke_device, mutation: Mutations::RevokeDevice
  end
end
