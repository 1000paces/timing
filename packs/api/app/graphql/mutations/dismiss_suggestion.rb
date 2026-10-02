module Mutations
  class DismissSuggestion < RulingMutation
    argument :event_id, ID
    argument :key, String

    def resolve(event_id:, key:)
      record(event: Event.find(event_id), kind: "dismiss_suggestion", payload: { suggestion_key: key })
    end
  end
end
