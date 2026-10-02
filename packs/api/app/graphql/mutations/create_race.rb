module Mutations
  class CreateRace < BaseMutation
    include RaceFields
    argument :event_id, ID
    argument :gender, String
    argument :scheduled_at_ms, Types::Millis

    def resolve(event_id:, **attrs)
      require_official!("admin")
      persist(Event.find(event_id).races.new(attrs), :race)
    end
  end
end
