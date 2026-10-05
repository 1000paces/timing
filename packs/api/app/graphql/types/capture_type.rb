module Types
  class CaptureType < BaseObject
    field :id, ID, null: false
    field :bib, String
    field :captured_at_ms, Millis, null: false
    field :lap, Integer, description: "Captures for this bib since its race started, including this one; null when not started"
    field :lap_ms, Millis, description: "Time since this bib's previous capture (or its race's start for lap 1)"
    field :typical_lap_ms, Millis, description: "Median of the race's other laps after lap 1; null until there are three"
    field :lap_flag, String, description: "missed (roughly double the typical lap), long, or short; null when normal"

    def lap = laps.lap
    def lap_ms = laps.lap_ms
    def typical_lap_ms = laps.typical_ms
    def lap_flag = laps.flag

    private

    # One calculator per event per request, shared by every capture in the list.
    def laps
      calculator = (context[:capture_laps] ||= {})[object.event_id] ||= CaptureLaps.new(object.event)
      calculator.info(object)
    end
  end
end
