module Mutations
  class RemoveRegistration < BaseMutation
    description "Remove a registration that has no captures (fix captured racers with rulings instead)"
    argument :id, ID

    def resolve(id:)
      require_official!("chief")
      registration = Registration.find(id)
      if registration.bib && Capture.exists?(event_id: registration.event_id, bib: registration.bib)
        return { errors: [ "Bib #{registration.bib} has captures and can't be removed" ] }
      end
      registration.destroy ? { errors: [] } : { errors: registration.errors.full_messages }
    end
  end
end
