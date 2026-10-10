module Mutations
  class InsertCrossing < RulingMutation
    include OfficiatingFix
    description "Add a missed crossing for a racer at a time"
    argument :event_id, ID
    argument :bib, String
    argument :at_ms, Types::Millis
    argument :checkpoint_id, ID, required: false, description: "Where (a course checkpoint); omit for the finish"

    def resolve(event_id:, bib:, at_ms:, checkpoint_id: nil)
      require_official!("chief")
      event = Event.find(event_id)
      bib = bib.strip
      refusal = registered!(event, bib)
      return refusal if refusal
      result, = racer_row(event, bib)
      start = result&.start_at_ms
      return refuse("A crossing can't be inserted before the race started") if start.nil? || at_ms < start
      if checkpoint_id && !event.checkpoints.exists?(id: checkpoint_id)
        return refuse("That checkpoint isn't on this event's course")
      end
      record(event:, kind: "insert_capture", payload: { bib:, at_ms:, checkpoint_id: }.compact)
    end
  end
end
