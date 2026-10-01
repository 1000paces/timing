module Results
  # --- Input: setup ---
  StartGroupDef = Data.define(:id, :finish_rule) # finish_rule: {"type"=>"fixed_laps","laps"=>n} | {"type"=>"timed","target_duration_ms"=>d}
  RaceDef = Data.define(:id, :start_group_id, :start_offset_ms)
  Entrant = Data.define(:bib, :race_id, :name)

  # --- Input: race log ---
  Capture = Data.define(:id, :device_id, :device_seq, :captured_at_ms, :clock_offset_ms, :bib)
  BibAssignment = Data.define(:id, :capture_id, :bib, :device_seq)
  Ruling = Data.define(:id, :kind, :payload, :created_at_ms) # payload: string-keyed hash

  Config = Data.define(:debounce_ms, :missed_low, :missed_high, :neighbor_low, :neighbor_high, :short_ratio, :match_window_ratio)
  Config::DEFAULT = Config.new(debounce_ms: 10_000, missed_low: 1.7, missed_high: 2.3, neighbor_low: 0.7,
                               neighbor_high: 1.3, short_ratio: 0.5, match_window_ratio: 0.15)

  Input = Data.define(:start_groups, :races, :entrants, :captures, :bib_assignments, :rulings, :now_ms, :config) do
    def initialize(start_groups:, races:, entrants:, captures:, bib_assignments: [], rulings: [], now_ms: 0, config: Config::DEFAULT)
      super
    end
  end

  # --- Derived ---
  Crossing = Data.define(:bib, :at_ms, :ref, :inserted) # ref: capture id, or ruling id for inserted crossings
  UnassignedCrossing = Data.define(:capture_id, :at_ms, :bib)
end
