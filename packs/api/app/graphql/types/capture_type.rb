module Types
  class CaptureType < BaseObject
    field :id, ID, null: false
    field :bib, String, description: "The resolved bib: an official's assignment, else the device's later entry, else what was typed"
    field :entered_bib, String, description: "The bib as typed at the line"
    field :captured_at_ms, Millis, null: false
    field :lap, Integer, description: "Captures for this bib since its race started, including this one; null when not started"
    field :lap_ms, Millis, description: "Time since this bib's previous capture (or its race's start for lap 1)"
    field :typical_lap_ms, Millis, description: "Median of the race's other laps after lap 1; null until there are three"
    field :lap_flag, String, description: "missed (roughly double the typical lap), long, or short; null when normal"

    def bib = calculator.bib(object)
    def entered_bib = object.bib
    def lap = laps.lap
    def lap_ms = laps.lap_ms
    def typical_lap_ms = laps.typical_ms
    def lap_flag = laps.flag

    private

    # One calculator per event per request, shared by every capture in the list.
    def calculator = (context[:capture_laps] ||= {})[object.event_id] ||= CaptureLaps.new(object.event)
    def laps = calculator.info(object)
  end
end
