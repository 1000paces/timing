module Types
  class CaptureType < BaseObject
    field :id, ID, null: false
    field :bib, String, description: "The resolved bib: an official's assignment, else the device's later entry, else what was typed"
    field :entered_bib, String, description: "The bib as typed at the line"
    field :bib_source, String, null: false, description: "RULING (an official assigned it), DEVICE (corrected later) or ENTERED"
    field :captured_at_ms, Millis, null: false, description: "The device's own clock"
    field :at_ms, Millis, null: false, description: "Hub time: the device's clock corrected by its offset"
    field :device_name, String, null: false
    field :mine, Boolean, null: false, description: "Recorded on the signed-in official's console"
    field :lap, Integer, description: "Captures for this bib since its race started, including this one; null when not started"
    field :lap_ms, Millis, description: "Time since this bib's previous capture (or its race's start for lap 1)"
    field :typical_lap_ms, Millis, description: "Median of the race's other laps after lap 1; null until there are three"
    field :lap_flag, String, description: "missed (roughly double the typical lap), long, or short; null when normal"

    def bib = calculator.bib(object)
    def entered_bib = object.bib
    def at_ms = object.captured_at_ms + object.clock_offset_ms.to_i
    def device_name = object.device.name

    def mine
      consoles = context[:console_devices] ||= {}
      consoles.fetch(object.event_id) { consoles[object.event_id] = ConsoleDevice.find(event: object.event, official: context[:current_official])&.id } == object.device_id
    end
    def bib_source = calculator.bib_source(object).to_s.upcase
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
