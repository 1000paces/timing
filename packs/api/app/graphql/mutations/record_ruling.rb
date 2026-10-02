module Mutations
  class RecordRuling < RulingMutation
    argument :event_id, ID
    argument :kind, Types::RulingKindEnum
    argument :payload, GraphQL::Types::JSON
    argument :reason, String, required: false

    def resolve(event_id:, kind:, payload:, reason: nil)
      record(event: Event.find(event_id), kind:, payload:, reason:)
    end
  end
end
