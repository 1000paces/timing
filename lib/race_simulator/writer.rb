module RaceSimulator
  # Records the simulation as a "Simulator" device would.
  class Writer
    def initialize(event:, device_name: "Simulator", checkpoint: nil)
      @event = event
      @checkpoint = checkpoint
      @device_name = device_name
    end

    def device
      @device ||= Device.find_by(event: @event, name: @device_name) || Device.pair!(event: @event, name: @device_name, checkpoint_id: @checkpoint&.id).first
    end

    def start_races(races, at_ms:)
      races.each { Ruling.create!(event: @event, kind: "set_race_start", payload: { "race_id" => it.id, "at_ms" => at_ms }) }
    end

    def set_lap_count(race, laps)
      Ruling.create!(event: @event, kind: "set_lap_count", payload: { "race_id" => race.id, "laps" => laps })
    end

    def capture(at_ms:, bib:) = Capture.record!(device:, at_ms:, bib:)
  end
end
