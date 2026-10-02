module Mutations
  class SetRaceStart < RulingMutation
    description "Override one race's start (held or delayed wave); defaults to hub time now"
    argument :race_id, ID
    argument :at_ms, Types::Millis, required: false

    def resolve(race_id:, at_ms: nil)
      race = Race.find(race_id)
      record(event: race.event, kind: "set_race_start", payload: { race_id: race.id, at_ms: at_ms || Clock.now_ms })
    end
  end
end
