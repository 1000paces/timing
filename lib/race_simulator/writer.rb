module RaceSimulator
  # Records the simulation as a "Simulator" device would. Its hash chain is a
  # placeholder: simulator entries never go through device sync verification.
  class Writer
    def initialize(event:, device_name: "Simulator")
      @event = event
      @device_name = device_name
    end

    def device
      @device ||= Device.find_by(event: @event, name: @device_name) || Device.pair!(event: @event, name: @device_name).first
    end

    def start_races(races, at_ms:)
      races.each { Ruling.create!(event: @event, kind: "set_race_start", payload: { "race_id" => it.id, "at_ms" => at_ms }) }
    end

    def set_lap_count(race, laps)
      Ruling.create!(event: @event, kind: "set_lap_count", payload: { "race_id" => race.id, "laps" => laps })
    end

    def capture(at_ms:, bib:)
      last = DeviceEntry.where(device:).order(:device_seq).last
      prev = last&.entry_hash || Digest::SHA256.hexdigest(device.id)
      id = SecureRandom.uuid_v7
      Capture.create!(id:, event: @event, device:, device_seq: (last&.device_seq || 0) + 1, captured_at_ms: at_ms,
                      clock_offset_ms: 0, bib:, prev_hash: prev, entry_hash: Digest::SHA256.hexdigest("#{prev}|#{id}|#{at_ms}|#{bib}"))
    end
  end
end
