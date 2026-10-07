# Builds the results engine's input from the database. The engine itself never
# touches ActiveRecord.
class ResultsSnapshot
  def self.compute(event, now_ms: (Time.now.to_r * 1000).to_i) = Results.compute(self.for(event, now_ms:))

  def self.for(event, now_ms:)
    Results::Input.new(
      races: event.races.map do
        Results::RaceDef.new(id: it.id, scheduled_at_ms: it.scheduled_at_ms, finish_with_leader: it.effective_finish_with_leader,
                             expected_laps: it.expected_laps)
      end,
      entrants: event.registrations.includes(:racer).map { Results::Entrant.new(bib: it.bib, race_id: it.race_id, name: it.racer.full_name) },
      captures: Capture.where(event:).map do
        Results::Capture.new(id: it.id, device_id: it.device_id, device_seq: it.device_seq, captured_at_ms: it.captured_at_ms,
                             clock_offset_ms: it.clock_offset_ms, bib: it.bib)
      end,
      bib_assignments: BibAssignment.where(event:).map do
        Results::BibAssignment.new(id: it.id, capture_id: it.capture_id, bib: it.bib, device_seq: it.device_seq)
      end,
      rulings: Ruling.where(event:).map { Results::Ruling.new(id: it.id, kind: it.kind, payload: it.payload, created_at_ms: it.created_at_ms) } +
               device_voids(event),
      now_ms:
    )
  end

  # A device's own void counts as a void_capture ruling for the engine.
  def self.device_voids(event)
    CaptureVoid.where(event:).map do
      Results::Ruling.new(id: "dv-#{it.id}", kind: "void_capture", payload: { "capture_id" => it.capture_id }, created_at_ms: it.received_at_ms)
    end
  end
end
