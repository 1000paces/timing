# Everything the racer panel shows for one bib, from the results engine (so it
# matches the standings) plus where each crossing came from and the fixes.
module RacerDetail
  module_function

  def for(event, bib)
    registration = event.registrations.includes(:racer, :race).find_by(bib:)
    raise GraphQL::ExecutionError, "No racer with bib #{bib} in this event" unless registration

    result = StandingsService.report(event).output.races.find { it.race_id == registration.race_id }
    row = result&.rows&.find { it.bib == bib }
    views = row&.crossings || []
    refs = views.map(&:ref)
    devices = Capture.where(id: refs).includes(:device).to_h { [ it.id, it.device.name ] }
    history = RulingHistory.new(event)
    inserts = history.rulings.select { refs.include?(it.id) }.to_h { [ it.id, it.official_id ] }
    concerns = refs.to_set
    fixes = history.rulings.reject { it.kind == "revert" }
                   .select { history.describer.bibs_for(it).include?(bib) || concerns.include?(it.payload["capture_id"]) }

    { bib:, name: registration.racer.full_name, race: registration.race, status: row&.status || :racing, place: row&.place,
      laps: row&.laps || 0, elapsed_ms: row&.elapsed_ms, gap_laps_down: row&.gap&.laps_down, gap_ms: row&.gap&.ms,
      start_at_ms: result&.start_at_ms, pull_at_ms: row&.pull_at_ms, finish_ref: row&.finish_ref, lap_positions: row&.lap_positions || [], splits: row&.splits || [],
      crossings: views.map do |v|
        source = v.inserted ? "inserted by #{history.official_name(inserts[v.ref]) || 'an official'}" : devices.fetch(v.ref, "a device")
        { ref: v.ref, at_ms: v.at_ms, inserted: v.inserted, kind: v.kind, checkpoint_id: v.checkpoint_id, lap: v.lap, lap_ms: v.lap_ms, source: }
      end,
      rulings: fixes.map { history.entry(it) } }
  end
end
