module Mutations
  class FireStart < RulingMutation
    description "GO: the start group's gun, at hub time"
    argument :start_group_id, ID

    def resolve(start_group_id:)
      require_official!("chief")
      group = StartGroup.find(start_group_id)
      record(event: group.event, kind: "set_group_start", payload: { start_group_id: group.id, at_ms: Clock.now_ms })
    end
  end
end
