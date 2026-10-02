module Mutations
  class RevertRuling < RulingMutation
    argument :ruling_id, ID
    argument :reason, String, required: false

    def resolve(ruling_id:, reason: nil)
      target = Ruling.find(ruling_id)
      record(event: target.event, kind: "revert", payload: { ruling_id: target.id }, reason:)
    end
  end
end
