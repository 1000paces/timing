module ResultsTestHelpers
  # Setup section for one race r1 (expected laps, start time, finish with leader).
  def setup_yaml(bibs: [ 1, 2, 3 ], laps: 3, start: 0, fwl: true)
    attrs = [ "id: r1", ("laps: #{laps}" if laps), ("start: #{start}" unless start.nil?), "fwl: #{fwl}" ].compact
    lines = [ "races:", "  - {#{attrs.join(', ')}}", "entrants:" ]
    lines += bibs.map { "  - {bib: #{it}, race: r1}" }
    lines.join("\n") + "\n"
  end

  def input_from(yaml) = Results::Fixture.parse(yaml).first

  def compact_rows(rows)
    rows.map { [ it.place, it.bib, it.status.to_s, it.laps, it.elapsed_ms && it.elapsed_ms / 1000 ] }
  end

  def normalize_rows(rows)
    rows.map { |place, bib, status, laps, elapsed| [ place, bib.to_s, status.to_s, laps, elapsed ] }
  end
end
