module Mutations
  class UpdateRegistration < BaseMutation
    description "Change a registration or its rider; arguments left out are unchanged, an explicit null clears bib or age"
    argument :id, ID
    argument :race_id, ID, required: false
    argument :bib, String, required: false
    argument :age, Integer, required: false
    argument :rider, Types::RiderInput, required: false

    field :registration, Types::RegistrationType
    field :warnings, [String], null: false

    def resolve(id:, **changes)
      require_official!("chief")
      registration = Registration.find(id)
      rider = registration.rider
      registration.race = registration.event.races.find(changes[:race_id]) if changes[:race_id]
      registration.bib = changes[:bib] if changes.key?(:bib)
      registration.age = changes[:age] if changes.key?(:age)
      rider.assign_attributes(changes[:rider].to_h) if changes[:rider]
      saved = Registration.transaction do
        (rider.save && registration.save) || raise(ActiveRecord::Rollback)
      end
      return { registration:, warnings: registration.eligibility_warnings, errors: [] } if saved
      { registration: nil, warnings: [], errors: rider.errors.full_messages + registration.errors.full_messages }
    end
  end
end
