module Mutations
  class RegisterRider < BaseMutation
    argument :race_id, ID
    argument :bib, String
    argument :rider, Types::RiderInput

    field :registration, Types::RegistrationType
    field :warnings, [String], null: false

    def resolve(race_id:, bib:, rider:)
      require_official!("admin")
      registration = RiderRegistrar.register(race: Race.find(race_id), bib:, rider_attrs: rider.to_h)
      return { registration: nil, warnings: [], errors: registration.errors.full_messages } unless registration.persisted?
      { registration:, warnings: registration.eligibility_warnings, errors: [] }
    end
  end
end
