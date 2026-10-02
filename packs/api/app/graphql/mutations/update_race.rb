module Mutations
  class UpdateRace < BaseMutation
    include RaceFields
    description "Change a race; arguments left out are unchanged, an explicit null clears"
    argument :id, ID
    argument :gender, String, required: false
    argument :scheduled_at_ms, Types::Millis, required: false

    def resolve(id:, **attrs)
      require_official!("admin")
      race = Race.find(id)
      race.assign_attributes(attrs)
      persist(race, :race)
    end
  end
end
