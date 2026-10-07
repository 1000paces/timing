module Types
  class MutationType < BaseObject
    field :create_event, mutation: Mutations::CreateEvent
    field :update_event, mutation: Mutations::UpdateEvent
    field :create_race, mutation: Mutations::CreateRace
    field :update_race, mutation: Mutations::UpdateRace
    field :delete_race, mutation: Mutations::DeleteRace
    field :register_racer, mutation: Mutations::RegisterRacer
    field :create_official, mutation: Mutations::CreateOfficial
    field :analyze_import, mutation: Mutations::AnalyzeImport
    field :import_registrations, mutation: Mutations::ImportRegistrations
    field :update_registration, mutation: Mutations::UpdateRegistration
    field :set_checked_in, mutation: Mutations::SetCheckedIn
    field :remove_registration, mutation: Mutations::RemoveRegistration
    field :assign_bibs, mutation: Mutations::AssignBibs
    field :set_racer_status, mutation: Mutations::SetRacerStatus
    field :set_race_start, mutation: Mutations::SetRaceStart
    field :set_lap_count, mutation: Mutations::SetLapCount
    field :record_ruling, mutation: Mutations::RecordRuling
    field :revert_ruling, mutation: Mutations::RevertRuling
    field :accept_suggestion, mutation: Mutations::AcceptSuggestion
    field :dismiss_suggestion, mutation: Mutations::DismissSuggestion
    field :publish_results, mutation: Mutations::PublishResults
    field :start_races, mutation: Mutations::StartRaces
    field :record_capture, mutation: Mutations::RecordCapture
    field :delete_capture, mutation: Mutations::DeleteCapture
    field :correct_capture_bib, mutation: Mutations::CorrectCaptureBib
    field :unstart_race, mutation: Mutations::UnstartRace
    field :create_pairing_token, mutation: Mutations::CreatePairingToken
    field :revoke_device, mutation: Mutations::RevokeDevice
  end
end
