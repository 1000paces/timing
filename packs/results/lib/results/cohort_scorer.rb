require "digest"
require "json"

module Results
  # Finish logic is decided per cohort (finish-with-leader races sharing a
  # scheduled start, or a single race); scoring is per race.
  class CohortScorer
    STATUS_KINDS = %w[dnf dns dsq].freeze

    RiderState = Data.define(:entrant, :race_start, :crossings, :counted, :status, :finish, :pull_at)
    Scored = Data.define(:races, :lap_count, :finish_open_at, :riders, :race_results)

    def initialize(input, races, resolved)
      @input = input
      @races = races.sort_by(&:id)
      @resolved = resolved
      rulings = resolved.rulings
      @rulings = rulings
      @flags = rulings.latest_by("flag_finish") { it.payload["bib"].to_s }
      @pulls = rulings.latest_by("pull") { it.payload["bib"].to_s }
      @statuses = rulings.all.select { STATUS_KINDS.include?(it.kind) }.group_by { it.payload["bib"].to_s }.transform_values(&:last)
    end

    def call
      races = @races
      starts = race_starts(races)
      race_ids = races.map(&:id)
      entrants = @input.entrants.select { race_ids.include?(it.race_id) }
      crossings = entrants.to_h { |e| [e.bib, post_start(e, starts[e.race_id])] }
      lap_count = resolve_lap_count
      finish_open_at = lap_count && crossings.values.filter_map { it[lap_count - 1] }.min_by { [it.at_ms, it.ref] }&.at_ms
      riders = entrants.map { |e| rider_state(e, starts[e.race_id], crossings[e.bib], finish_open_at) }

      race_results = races.map do |race|
        state = if starts[race.id].nil? then :not_started
                elsif finish_open_at then :finish_open
                else :in_progress
                end
        rows = Standings.rows(riders.select { it.entrant.race_id == race.id })
        RaceResult.new(race_id: race.id, state:, lap_count:, publication: :provisional, rows:, digest: digest(lap_count, rows),
                       start_at_ms: starts[race.id])
      end
      Scored.new(races:, lap_count:, finish_open_at:, riders:, race_results:)
    end

    private

    # Fingerprint of what the race's standings show; publication compares against it.
    def digest(lap_count, rows)
      Digest::SHA256.hexdigest(JSON.generate([lap_count, rows.map { [it.place, it.bib, it.status.to_s, it.laps, it.elapsed_ms, it.lap_times_ms] }]))
    end

    # The latest lap count set for any race in the cohort; else the races'
    # expected laps if they agree; else not set.
    def resolve_lap_count
      ids = @races.map(&:id)
      latest = @rulings.of("set_lap_count").select { ids.include?(it.payload["race_id"]) }.last
      return latest.payload.fetch("laps") if latest
      expected = @races.map(&:expected_laps).uniq
      expected.first if expected.size == 1
    end

    # Each race starts at its own latest set_race_start (waves are started by hand).
    def race_starts(races)
      starts = @rulings.latest_by("set_race_start") { it.payload["race_id"] }
      races.to_h { |r| [r.id, starts[r.id]&.payload&.fetch("at_ms")] }
    end

    def post_start(entrant, start)
      return [] unless start
      @resolved.crossings_by_bib.fetch(entrant.bib, []).select { it.at_ms >= start }
    end

    def rider_state(entrant, start, crossings, finish_open_at)
      finish = finish_crossing(entrant.bib, crossings, finish_open_at)
      pull_at = @pulls[entrant.bib]&.payload&.fetch("at_ms")
      pull_at = nil if pull_at && finish && finish.at_ms <= pull_at # a pull at/after the finish does not undo it
      status = if (s = @statuses[entrant.bib]) then s.kind.to_sym
               elsif pull_at then :pulled
               elsif finish then :finished
               else :racing
               end
      counted = if status == :pulled then crossings.select { it.at_ms <= pull_at }
                elsif finish then crossings[0..crossings.index(finish)]
                else crossings
                end
      RiderState.new(entrant:, race_start: start, crossings:, counted:, status:, finish: (finish if status == :finished), pull_at:)
    end

    # Earliest of: the flagged crossing (early checkered flag) and the first
    # crossing once the finish is open. A flag on a crossing this rider no longer
    # has (voided or reassigned) is ignored.
    def finish_crossing(bib, crossings, finish_open_at)
      flag_ref = @flags[bib]&.payload&.fetch("capture_id")
      flag_ref = @resolved.aliases.fetch(flag_ref, flag_ref)
      candidates = [crossings.find { it.ref == flag_ref }]
      candidates << crossings.find { it.at_ms >= finish_open_at } if finish_open_at
      candidates.compact.min_by { [it.at_ms, it.ref] }
    end
  end
end
