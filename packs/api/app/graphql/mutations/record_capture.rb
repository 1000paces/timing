module Mutations
  class RecordCapture < BaseMutation
    description "Record a line crossing from the console at hub time now; a blank bib is assigned later in review"
    argument :event_id, ID
    argument :bib, String, required: false

    field :capture, Types::CaptureType

    def resolve(event_id:, bib: nil)
      official = require_official!("timer")
      event = Event.find(event_id)
      { capture: Capture.record!(device: ConsoleDevice.for(event:, official:), at_ms: Clock.now_ms, bib:), errors: [] }
    end
  end
end
