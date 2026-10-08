module Mutations
  class UpdateRegistration < BaseMutation
    description "Change a registration or its racer; arguments left out are unchanged, an explicit null clears bib or age"
    argument :id, ID
    argument :race_id, ID, required: false
    argument :bib, String, required: false
    argument :age, Integer, required: false
    argument :racer, Types::RacerInput, required: false

    field :registration, Types::RegistrationType
    field :warnings, [ String ], null: false

    def resolve(id:, **changes)
      require_official!("chief")
      registration = Registration.find(id)
      racer = registration.racer
      registration.race = registration.event.races.find(changes[:race_id]) if changes[:race_id]
      registration.bib = changes[:bib] if changes.key?(:bib)
      registration.age = changes[:age] if changes.key?(:age)
      racer.assign_attributes(changes[:racer].to_h) if changes[:racer]
      saved = Registration.transaction do
        (racer.save && registration.save) || raise(ActiveRecord::Rollback)
      end
      return { registration:, warnings: registration.eligibility_warnings, errors: [] } if saved
      { registration: nil, warnings: [], errors: racer.errors.full_messages + registration.errors.full_messages }
    end
  end
end
