require "digest"
require "json"

module Results
  # Scores one course race (point to point / single loop): each racer's first
  # crossing at each checkpoint after the start counts, and their first finish
  # crossing finishes them. Finish-with-leader, lap counts and flags don't apply.
  class CourseScorer
    STATUS_KINDS = %w[dnf dns dsq].freeze

    # passes: checkpoint id (nil: the finish) => the counted crossing there.
    CourseRacer = Data.define(:entrant, :race_start, :passes, :status, :finish, :pull_at, :seen, :dropped)
    Scored = Data.define(:race, :start_at, :racers, :race_result)

    def initialize(input, race, resolved)
      @input = input
      @race = race
      @resolved = resolved
      rulings = resolved.rulings
      @start = rulings.latest_by("set_race_start") { it.payload["race_id"] }[race.id]&.payload&.fetch("at_ms")
      @pulls = rulings.latest_by("pull") { it.payload["bib"].to_s }
      @statuses = rulings.all.select { STATUS_KINDS.include?(it.kind) }.group_by { it.payload["bib"].to_s }.transform_values(&:last)
    end

    def call
      racers = @input.entrants.select { it.race_id == @race.id }.map { racer(it) }
      rows = CourseStandings.rows(racers, @race.course)
      state = if @start.nil? then :not_started
      elsif racers.any? { it.finish } then :finish_open
      else :in_progress
      end
      result = RaceResult.new(race_id: @race.id, state:, lap_count: nil, publication: :provisional, rows:, digest: digest(rows),
                              start_at_ms: @start, flag_out_at_ms: nil, flag_out_leader: nil)
      Scored.new(race: @race, start_at: @start, racers:, race_result: result)
    end

    private

    def digest(rows)
      Digest::SHA256.hexdigest(JSON.generate(rows.map { [ it.place, it.bib, it.status.to_s, it.elapsed_ms, it.splits.map(&:at_ms) ] }))
    end

    def racer(entrant)
      bib = entrant.bib
      seen = @resolved.crossings_by_bib.fetch(bib, [])
      known = @race.course.map(&:id).to_set
      after_start = @start ? seen.select { it.at_ms >= @start && known.include?(it.checkpoint_id) } : []
      finish = after_start.find { it.checkpoint_id.nil? }
      pull_at = @pulls[bib]&.payload&.fetch("at_ms")
      pull_at = nil if pull_at && finish && finish.at_ms <= pull_at # a pull at/after the finish does not undo it
      finish = nil if pull_at
      last_at = finish&.at_ms || pull_at
      in_play = last_at ? after_start.select { it.at_ms <= last_at } : after_start
      passes = in_play.group_by(&:checkpoint_id).transform_values(&:first)
      status = if (s = @statuses[bib]) then s.kind.to_sym
      elsif pull_at then :pulled
      elsif finish then :finished
      else :racing
      end
      CourseRacer.new(entrant:, race_start: @start, passes:, status:, finish: (finish if status == :finished), pull_at:,
                      seen:, dropped: @resolved.dropped.fetch(bib, []))
    end
  end
end
