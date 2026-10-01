module Results
  # Spec §4.2: finish logic is decided per start group; scoring is per race.
  class GroupScorer
    STATUS_KINDS = %w[dnf dns dsq].freeze

    RiderState = Data.define(:entrant, :race_start, :crossings, :counted, :status, :finish, :pull_at)
    Scored = Data.define(:group, :lap_count, :finish_open_at, :riders, :race_results)

    def initialize(input, group, resolved)
      @input = input
      @group = group
      @resolved = resolved
      rulings = resolved.rulings
      @rulings = rulings
      @flags = rulings.latest_by("flag_finish") { it.payload["bib"].to_s }
      @pulls = rulings.latest_by("pull") { it.payload["bib"].to_s }
      @statuses = rulings.all.select { STATUS_KINDS.include?(it.kind) }.group_by { it.payload["bib"].to_s }.transform_values(&:last)
    end

    def call
      races = @input.races.select { it.start_group_id == @group.id }.sort_by(&:id)
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
        RaceResult.new(race_id: race.id, state:, lap_count:, publication: :provisional,
                       rows: Standings.rows(riders.select { it.entrant.race_id == race.id }))
      end
      Scored.new(group: @group, lap_count:, finish_open_at:, riders:, race_results:)
    end

    private

    def resolve_lap_count
      rule = @group.finish_rule
      case rule["type"]
      when "fixed_laps" then rule["laps"]
      when "timed" then @rulings.latest_by("set_lap_count") { it.payload["start_group_id"] }[@group.id]&.payload&.fetch("laps")
      end
    end

    def race_starts(races)
      gun = @rulings.latest_by("set_group_start") { it.payload["start_group_id"] }[@group.id]&.payload&.fetch("at_ms")
      overrides = @rulings.latest_by("set_race_start") { it.payload["race_id"] }
      races.to_h { |r| [r.id, overrides[r.id]&.payload&.fetch("at_ms") || (gun && gun + r.start_offset_ms)] }
    end

    def post_start(entrant, start)
      return [] unless start
      @resolved.crossings_by_bib.fetch(entrant.bib, []).select { it.at_ms >= start }
    end

    def rider_state(entrant, start, crossings, finish_open_at)
      finish = finish_crossing(entrant.bib, crossings, finish_open_at)
      pull_at = @pulls[entrant.bib]&.payload&.fetch("at_ms")
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
