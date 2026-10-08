module Mutations
  class PullRacer < RulingMutation
    include OfficiatingFix
    description "Pull a racer: crossings after the time don't count; placed after those still racing"
    argument :event_id, ID
    argument :bib, String
    argument :at_ms, Types::Millis

    def resolve(event_id:, bib:, at_ms:)
      require_official!("chief")
      event = Event.find(event_id)
      registered!(event, bib) || record(event:, kind: "pull", payload: { bib: bib.strip, at_ms: })
    end
  end
end
