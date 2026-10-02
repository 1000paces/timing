module Mutations
  class SetLapCount < RulingMutation
    description "Set the start group's lap count; overrides the finish rule (fixed or timed)"
    argument :start_group_id, ID
    argument :laps, Integer

    def resolve(start_group_id:, laps:)
      require_official!("chief")
      group = StartGroup.find(start_group_id)
      record(event: group.event, kind: "set_lap_count", payload: { start_group_id: group.id, laps: })
    end
  end
end
