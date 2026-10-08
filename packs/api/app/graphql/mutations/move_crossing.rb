module Mutations
  class MoveCrossing < RulingMutation
    include OfficiatingFix
    description "Give a captured crossing to another (registered) bib"
    argument :event_id, ID
    argument :capture_id, ID
    argument :bib, String

    def resolve(event_id:, capture_id:, bib:)
      require_official!("chief")
      event = Event.find(event_id)
      return refuse("That crossing isn't part of this event") unless Capture.exists?(id: capture_id, event:)
      registered!(event, bib) || record(event:, kind: "assign_bib", payload: { capture_id:, bib: bib.strip })
    end
  end
end
