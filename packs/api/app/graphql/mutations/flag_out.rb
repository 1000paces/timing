module Mutations
  class FlagOut < RulingMutation
    description "The finish flag is out for the race's wave: from then on everyone but the wave's leader finishes " \
                "on their next crossing. Defaults to hub time now"
    argument :race_id, ID
    argument :at_ms, Types::Millis, required: false

    def resolve(race_id:, at_ms: nil)
      race = Race.find(race_id)
      # Timers too: it records what happened at the line (undoing it stays with chiefs).
      record(event: race.event, kind: "flag_out", payload: { race_id: race.id, at_ms: at_ms || Clock.now_ms }, role: "timer")
    end
  end
end
