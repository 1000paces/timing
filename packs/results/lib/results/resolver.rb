module Results
  # Spec §4.1: turns the raw log into per-bib crossings plus unassigned captures.
  class Resolver
    Resolved = Data.define(:crossings_by_bib, :unassigned, :aliases, :rulings, :unsynced_devices)

    def initialize(input)
      @input = input
    end

    def call
      rulings = ActiveRulings.new(@input.rulings)
      registered = @input.entrants.map(&:bib).to_set
      voided = rulings.of("void_capture").map { it.payload["capture_id"] }.to_set
      overrides = rulings.latest_by("assign_bib") { it.payload["capture_id"] }
      device_bibs = @input.bib_assignments.uniq(&:id).group_by(&:capture_id)
                          .transform_values { |list| list.max_by { [it.device_seq, it.id] }.bib }

      crossings = []
      unassigned = []
      unsynced = Set.new
      @input.captures.uniq(&:id).each do |c|
        next if voided.include?(c.id)
        unsynced << c.device_id if c.clock_offset_ms.nil?
        at = c.captured_at_ms + (c.clock_offset_ms || 0)
        bib = (overrides[c.id]&.payload&.fetch("bib") || device_bibs[c.id] || c.bib)&.to_s
        if bib && registered.include?(bib)
          crossings << Crossing.new(bib:, at_ms: at, ref: c.id, inserted: false)
        else
          unassigned << UnassignedCrossing.new(capture_id: c.id, at_ms: at, bib:)
        end
      end

      rulings.of("insert_capture").each do |r|
        bib = r.payload["bib"].to_s
        crossings << Crossing.new(bib:, at_ms: r.payload["at_ms"], ref: r.id, inserted: true) if registered.include?(bib)
      end

      by_bib, aliases = debounce(crossings)
      Resolved.new(crossings_by_bib: by_bib, unassigned: unassigned.sort_by { [it.at_ms, it.capture_id] },
                   aliases:, rulings:, unsynced_devices: unsynced.to_a.sort)
    end

    private

    # Collapses taps for the same bib that fall within the debounce window of the
    # last kept crossing, keeping the earliest. Returns [by_bib, dropped_ref => kept_ref].
    def debounce(crossings)
      aliases = {}
      by_bib = crossings.group_by(&:bib).transform_values do |list|
        list.sort_by { [it.at_ms, it.ref] }.each_with_object([]) do |c, kept|
          if kept.any? && c.at_ms - kept.last.at_ms < @input.config.debounce_ms
            aliases[c.ref] = kept.last.ref
          else
            kept << c
          end
        end
      end
      [by_bib, aliases]
    end
  end
end
