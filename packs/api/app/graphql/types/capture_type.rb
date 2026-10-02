module Types
  class CaptureType < BaseObject
    field :id, ID, null: false
    field :bib, String
    field :captured_at_ms, Millis, null: false
    field :lap, Integer, description: "Captures for this bib since its race started, including this one; null when not started"

    # One calculator per event per request, shared by every capture in the list.
    def lap
      laps = (context[:capture_laps] ||= {})[object.event_id] ||= CaptureLaps.new(object.event)
      laps.lap(object)
    end
  end
end
