module ResultsTestHelpers
  # Setup section for a single start group g1 with one race r1.
  def setup_yaml(bibs: [1, 2, 3], finish_rule: "{type: fixed_laps, laps: 3}", gun: 0)
    group = "  - {id: g1, finish_rule: #{finish_rule}#{gun.nil? ? '' : ", gun: #{gun}"}}"
    lines = ["start_groups:", group, "races:", "  - {id: r1, group: g1}", "entrants:"]
    lines += bibs.map { "  - {bib: #{it}, race: r1}" }
    lines.join("\n") + "\n"
  end

  def input_from(yaml) = Results::Fixture.parse(yaml).first

  def compact_rows(rows)
    rows.map { [it.place, it.bib, it.status.to_s, it.laps, it.elapsed_ms && it.elapsed_ms / 1000] }
  end

  def normalize_rows(rows)
    rows.map { |place, bib, status, laps, elapsed| [place, bib.to_s, status.to_s, laps, elapsed] }
  end
end
