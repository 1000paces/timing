module Mutations
  # A walk-up on the day: registered and checked in at once; bib optional.
  class RegisterRacer < BaseMutation
    argument :race_id, ID
    argument :bib, String, required: false
    argument :age, Integer, required: false
    argument :racer, Types::RacerInput

    field :registration, Types::RegistrationType
    field :warnings, [String], null: false

    def resolve(race_id:, racer:, bib: nil, age: nil)
      require_official!("chief")
      registration = RacerRegistrar.register(race: Race.find(race_id), bib:, racer_attrs: racer.to_h, age:)
      return { registration: nil, warnings: [], errors: registration.errors.full_messages } unless registration.persisted?
      registration.check_in!(at_ms: Clock.now_ms)
      { registration:, warnings: registration.eligibility_warnings, errors: [] }
    end
  end
end
