require "yaml"

module Results
  # Builds an Input from a compact YAML race description (times in seconds).
  # races: [{id, scheduled (default 0), fwl (finish with leader, default true),
  #          laps (expected laps), start (adds a set_race_start ruling)}]
  module Fixture
    module_function

    def load(path) = parse(File.read(path))

    def parse(yaml)
      data = YAML.safe_load(yaml)
      ms = ->(seconds) { seconds.nil? ? nil : (seconds * 1000).round }
      seqs = Hash.new(0)
      next_seq = ->(device) { seqs[device] += 1 }
      devices = {}

      captures = []
      (data["crossings"] || {}).each do |bib, times|
        times.each_with_index do |t, i|
          id = "c-#{bib}-#{i + 1}"
          devices[id] = "d1"
          at, checkpoint = t.is_a?(Hash) ? [ t["at"], t["cp"] ] : [ t, nil ]
          captures << Capture.new(id:, device_id: "d1", device_seq: next_seq.("d1"), captured_at_ms: ms.(at), clock_offset_ms: 0,
                                  bib: bib.to_s, checkpoint_id: checkpoint)
        end
      end
      (data["captures"] || []).each do |c|
        device = c.fetch("device", "d1")
        devices[c["id"]] = device
        captures << Capture.new(id: c["id"], device_id: device, device_seq: next_seq.(device), captured_at_ms: ms.(c["at"]),
                                clock_offset_ms: c.key?("offset_ms") ? c["offset_ms"] : 0, bib: c["bib"]&.to_s)
      end
      (data["unassigned"] || []).each_with_index do |t, i|
        id = "u-#{i + 1}"
        devices[id] = "d1"
        captures << Capture.new(id:, device_id: "d1", device_seq: next_seq.("d1"), captured_at_ms: ms.(t), clock_offset_ms: 0, bib: nil)
      end

      assignments = (data["bib_assignments"] || []).map do |b|
        BibAssignment.new(id: b["id"], capture_id: b["capture"], bib: b["bib"].to_s, device_seq: next_seq.(devices.fetch(b["capture"])))
      end

      races = data.fetch("races")
      rulings = races.select { it.key?("start") }.map do |r|
        Ruling.new(id: "start-#{r['id']}", kind: "set_race_start", payload: { "race_id" => r["id"], "at_ms" => ms.(r["start"]) }, created_at_ms: 0)
      end
      (data["rulings"] || []).each_with_index do |r, i|
        payload = r.except("id", "kind", "created").to_h do |k, v|
          case k
          when "at" then [ "at_ms", ms.(v) ]
          when "bib" then [ "bib", v&.to_s ]
          when "cp" then [ "checkpoint_id", v ]
          else [ k, v ]
          end
        end
        rulings << Ruling.new(id: r.fetch("id", "r-#{i + 1}"), kind: r.fetch("kind"), payload:, created_at_ms: ms.(r.fetch("created", i + 1)))
      end

      input = Input.new(
        races: races.map do
          RaceDef.new(id: it["id"], scheduled_at_ms: ms.(it.fetch("scheduled", 0)), finish_with_leader: it.fetch("fwl", true),
                      expected_laps: it["laps"], course: course(it, ms))
        end,
        entrants: data.fetch("entrants").map { Entrant.new(bib: it["bib"].to_s, race_id: it["race"], name: it.fetch("name", "Racer #{it['bib']}")) },
        captures:, bib_assignments: assignments, rulings:, now_ms: ms.(data.fetch("now", 0))
      )
      [ input, data["expect"] || {} ]
    end

    # A race's course: its checkpoints in order, then the finish (id nil).
    def course(race, ms)
      return nil unless race.key?("course")
      points = race["course"].each_with_index.map do |c, i|
        Checkpoint.new(id: c.fetch("id"), name: c.fetch("name", c["id"]), position: i + 1, distance_km: c["km"], cutoff_at_ms: ms.(c["cutoff"]))
      end
      points + [ Checkpoint.new(id: nil, name: "Finish", position: points.size + 1, distance_km: race["finish_km"], cutoff_at_ms: ms.(race["finish_cutoff"])) ]
    end
  end
end
