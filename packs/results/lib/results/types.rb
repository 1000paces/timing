module Results
  # --- Input: setup ---
  # finish_with_leader: the race's effective setting (its own override, else the event's).
  RaceDef = Data.define(:id, :scheduled_at_ms, :finish_with_leader, :expected_laps)
  Entrant = Data.define(:bib, :race_id, :name)

  # --- Input: race log ---
  Capture = Data.define(:id, :device_id, :device_seq, :captured_at_ms, :clock_offset_ms, :bib)
  BibAssignment = Data.define(:id, :capture_id, :bib, :device_seq)
  Ruling = Data.define(:id, :kind, :payload, :created_at_ms) # payload: string-keyed hash

  Config = Data.define(:debounce_ms, :missed_low, :missed_high, :neighbor_low, :neighbor_high, :short_ratio, :match_window_ratio)
  Config::DEFAULT = Config.new(debounce_ms: 10_000, missed_low: 1.7, missed_high: 2.3, neighbor_low: 0.7,
                               neighbor_high: 1.3, short_ratio: 0.5, match_window_ratio: 0.15)

  Input = Data.define(:races, :entrants, :captures, :bib_assignments, :rulings, :now_ms, :config) do
    def initialize(races:, entrants:, captures:, bib_assignments: [], rulings: [], now_ms: 0, config: Config::DEFAULT)
      super
    end
  end

  # --- Derived ---
  Crossing = Data.define(:bib, :at_ms, :ref, :inserted) # ref: capture id, or ruling id for inserted crossings
  UnassignedCrossing = Data.define(:capture_id, :at_ms, :bib)

  # --- Output ---
  # kind: :lap, :finish, :duplicate, :before_start, :after_finish, :after_pull;
  # lap / lap_ms only for counted crossings (lap and finish).
  CrossingView = Data.define(:ref, :at_ms, :inserted, :kind, :lap, :lap_ms)
  RacerResult = Data.define(:place, :bib, :name, :status, :laps, :elapsed_ms, :gap, :lap_times_ms,
                            :crossings, :lap_positions, :pull_at_ms, :finish_ref)
  Gap = Data.define(:laps_down, :ms) # ms only when on the same lap as the race leader
  # flag_out_leader: the bib the wave's flag let ride on to the lap count, if any.
  RaceResult = Data.define(:race_id, :state, :lap_count, :publication, :rows, :digest, :start_at_ms, :flag_out_at_ms, :flag_out_leader)
  Suggestion = Data.define(:key, :kind, :bib, :race_id, :message, :fix) # fix: ruling-shaped string-keyed hash, or nil
  Output = Data.define(:races, :suggestions, :unassigned)
end
