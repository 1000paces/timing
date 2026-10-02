module Mutations
  class RecordRuling < RulingMutation
    argument :event_id, ID
    argument :kind, Types::RulingKindEnum
    argument :payload, GraphQL::Types::JSON
    argument :reason, String, required: false

    def resolve(event_id:, kind:, payload:, reason: nil)
      require_official!("chief")
      return refuse("payload must be a JSON object") unless payload.is_a?(Hash)
      record(event: Event.find(event_id), kind:, payload:, reason:)
    end
  end
end
