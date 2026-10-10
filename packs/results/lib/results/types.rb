module Results
  # --- Input: setup ---
  # finish_with_leader: the race's effective setting (its own override, else the event's).
  # course: nil for a laps race; for a course race its checkpoints in order, ending with the finish (id nil).
  RaceDef = Data.define(:id, :scheduled_at_ms, :finish_with_leader, :expected_laps, :course) do
    def initialize(course: nil, **) = super
  end
  # A timing point on a course; id nil is the finish. cutoff_at_ms: a clock time, or nil.
  Checkpoint = Data.define(:id, :name, :position, :distance_km, :cutoff_at_ms)
  Entrant = Data.define(:bib, :race_id, :name)

  # --- Input: race log ---
  # checkpoint_id: where it was taken; nil is the finish line.
  Capture = Data.define(:id, :device_id, :device_seq, :captured_at_ms, :clock_offset_ms, :bib, :checkpoint_id) do
    def initialize(checkpoint_id: nil, **) = super
  end
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
  Crossing = Data.define(:bib, :at_ms, :ref, :inserted, :checkpoint_id) do # ref: capture id, or ruling id for inserted crossings
    def initialize(checkpoint_id: nil, **) = super
  end
  UnassignedCrossing = Data.define(:capture_id, :at_ms, :bib)

  # --- Output ---
  # kind: :lap, :finish, :split (a counted checkpoint pass), :duplicate, :before_start, :after_finish, :after_pull;
  # lap / lap_ms only for counted laps.
  CrossingView = Data.define(:ref, :at_ms, :inserted, :kind, :lap, :lap_ms, :checkpoint_id) do
    def initialize(checkpoint_id: nil, **) = super
  end
  RacerResult = Data.define(:place, :bib, :name, :status, :laps, :elapsed_ms, :gap, :lap_times_ms,
                            :crossings, :lap_positions, :pull_at_ms, :finish_ref, :splits) do
    def initialize(splits: [], **) = super
  end
  # One checkpoint (or the finish, checkpoint_id nil) of a course racer's result; times nil when missed.
  Split = Data.define(:checkpoint_id, :at_ms, :elapsed_ms, :segment_ms, :ref, :inserted)
  Gap = Data.define(:laps_down, :ms) # ms only when on the same lap as the race leader
  # flag_out_leader: the bib the wave's flag let ride on to the lap count, if any.
  RaceResult = Data.define(:race_id, :state, :lap_count, :publication, :rows, :digest, :start_at_ms, :flag_out_at_ms, :flag_out_leader)
  Suggestion = Data.define(:key, :kind, :bib, :race_id, :message, :fix) # fix: ruling-shaped string-keyed hash, or nil
  Output = Data.define(:races, :suggestions, :unassigned)
end
