module Mutations
  class SetCheckedIn < BaseMutation
    description "Check a racer in (at hub time now), or undo it"
    argument :registration_id, ID
    argument :checked_in, Boolean

    field :registration, Types::RegistrationType

    def resolve(registration_id:, checked_in:)
      require_official!("chief")
      registration = Registration.find(registration_id)
      checked_in ? registration.check_in!(at_ms: Clock.now_ms) : registration.undo_check_in!
      { registration:, errors: [] }
    end
  end
end
