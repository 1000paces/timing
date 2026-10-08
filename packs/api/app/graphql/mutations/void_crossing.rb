module Mutations
  # Void a crossing: a capture gets a void_capture ruling; an inserted crossing's
  # insert is undone (there is no tap to void).
  class VoidCrossing < RulingMutation
    argument :event_id, ID
    argument :ref, String

    def resolve(event_id:, ref:)
      require_official!("chief")
      event = Event.find(event_id)
      if Capture.exists?(id: ref, event:)
        record(event:, kind: "void_capture", payload: { capture_id: ref })
      elsif (insert = Ruling.find_by(id: ref, event:, kind: "insert_capture"))
        record(event:, kind: "revert", payload: { ruling_id: insert.id })
      else
        refuse("That crossing isn't part of this event")
      end
    end
  end
end
