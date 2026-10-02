require "yaml"

module Results
  # Builds an Input from a compact YAML race description (times in seconds).
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
          captures << Capture.new(id:, device_id: "d1", device_seq: next_seq.("d1"), captured_at_ms: ms.(t), clock_offset_ms: 0, bib: bib.to_s)
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

      groups = data.fetch("start_groups")
      rulings = groups.select { it.key?("gun") }.map do |g|
        Ruling.new(id: "gun-#{g['id']}", kind: "set_group_start", payload: { "start_group_id" => g["id"], "at_ms" => ms.(g["gun"]) }, created_at_ms: 0)
      end
      (data["rulings"] || []).each_with_index do |r, i|
        payload = r.except("id", "kind", "created").to_h do |k, v|
          case k
          when "at" then ["at_ms", ms.(v)]
          when "bib" then ["bib", v&.to_s]
          else [k, v]
          end
        end
        rulings << Ruling.new(id: r.fetch("id", "r-#{i + 1}"), kind: r.fetch("kind"), payload:, created_at_ms: ms.(r.fetch("created", i + 1)))
      end

      input = Input.new(
        start_groups: groups.map { StartGroupDef.new(id: it["id"], finish_rule: it.fetch("finish_rule")) },
        races: data.fetch("races").map { RaceDef.new(id: it["id"], start_group_id: it["group"]) },
        entrants: data.fetch("entrants").map { Entrant.new(bib: it["bib"].to_s, race_id: it["race"], name: it.fetch("name", "Rider #{it['bib']}")) },
        captures:, bib_assignments: assignments, rulings:, now_ms: ms.(data.fetch("now", 0))
      )
      [input, data["expect"] || {}]
    end
  end
end
