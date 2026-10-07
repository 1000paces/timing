module Results
  # Spec §4.4: suggestions only — never modifies data.
  class Anomalies
    Segment = Data.define(:index, :from_ref, :from_at, :to, :ms)

    def self.median(values)
      sorted = values.sort
      mid = sorted.size / 2
      (sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0).to_f
    end

    def self.segments_for(racer)
      return [] unless racer.race_start
      prev_ref = "start"
      prev_at = racer.race_start
      racer.counted.each_with_index.map do |c, i|
        seg = Segment.new(index: i + 1, from_ref: prev_ref, from_at: prev_at, to: c, ms: c.at_ms - prev_at)
        prev_ref = c.ref
        prev_at = c.at_ms
        seg
      end
    end

    # Typical lap times for one race (see spec §4.4 "Reference lap time").
    class RaceLaps
      def initialize(racers)
        @segments = racers.to_h { [it.entrant.bib, Anomalies.segments_for(it)] }
      end

      def segments(bib) = @segments.fetch(bib)

      def typical(bib, index, exclude)
        base = own_median(bib, exclude)
        return (base && start_factor && base * start_factor) if index == 1
        base || race_median(bib, index)
      end

      private

      def own_median(bib, exclude)
        laps = @segments[bib].select { it.index >= 2 && !exclude.include?(it.index) }.map(&:ms)
        laps.any? ? Anomalies.median(laps) : nil
      end

      def race_median(bib, index)
        laps = @segments.except(bib).values.filter_map { |segs| segs.find { it.index == index }&.ms }
        laps.any? ? Anomalies.median(laps) : nil
      end

      # How long lap 1 runs relative to a normal lap, across the race.
      def start_factor
        return @start_factor if defined?(@start_factor)
        ratios = @segments.filter_map do |bib, segs|
          base = own_median(bib, [])
          segs.first.ms / base if segs.any? && base&.positive?
        end
        @start_factor = ratios.any? ? Anomalies.median(ratios) : nil
      end
    end

    def initialize(input, resolved, scored_cohorts)
      @input = input
      @config = input.config
      @resolved = resolved
      @cohorts = scored_cohorts
    end

    def call
      dismissed = @resolved.rulings.of("dismiss_suggestion").map { it.payload["suggestion_key"] }.to_set
      (lap_suggestions + lapping_suggestions + clock_suggestions + unassigned_suggestions)
        .reject { dismissed.include?(it.key) }
        .sort_by(&:key)
    end

    private

    def lap_suggestions
      @cohorts.flat_map do |cohort|
        cohort.racers.group_by { it.entrant.race_id }.flat_map do |race_id, racers|
          laps = RaceLaps.new(racers)
          racers.flat_map { |r| racer_lap_suggestions(r.entrant.bib, race_id, laps) }
        end
      end
    end

    def racer_lap_suggestions(bib, race_id, laps)
      own = laps.segments(bib)
      own.filter_map do |seg|
        ref = laps.typical(bib, seg.index, [seg.index])
        next unless ref&.positive?
        ratio = seg.ms / ref
        if ratio.between?(@config.missed_low, @config.missed_high) && neighbors_normal?(bib, seg, own, laps)
          missed(bib, race_id, seg, ref)
        elsif ratio < @config.short_ratio && !seg.to.inserted && !long_neighbor?(bib, seg, own, laps)
          Suggestion.new(key: "short:#{bib}:#{seg.from_ref}:#{seg.to.ref}", kind: :suspected_duplicate, bib:, race_id:,
                         message: "Bib #{bib} lap #{seg.index} took #{fmt(seg.ms)}, much shorter than typical #{fmt(ref)} — duplicate tap or wrong bib?",
                         fix: { "kind" => "void_capture", "capture_id" => seg.to.ref })
        end
      end
    end

    def neighbors_normal?(bib, seg, own, laps)
      own.select { (it.index - seg.index).abs == 1 }.all? do |n|
        ref = laps.typical(bib, n.index, [seg.index, n.index])
        ref.nil? || (n.ms / ref).between?(@config.neighbor_low, @config.neighbor_high)
      end
    end

    # A long adjacent lap means a missed crossing is distorting the reference.
    def long_neighbor?(bib, seg, own, laps)
      own.select { (it.index - seg.index).abs == 1 }.any? do |n|
        ref = laps.typical(bib, n.index, [n.index])
        ref&.positive? && n.ms / ref >= @config.missed_low
      end
    end

    def missed(bib, race_id, seg, ref)
      mid = (seg.from_at + seg.to.at_ms) / 2
      window = ref * @config.match_window_ratio
      match = @resolved.unassigned.select { (it.at_ms - mid).abs <= window }.min_by { [(it.at_ms - mid).abs, it.capture_id] }
      fix = if match then { "kind" => "assign_bib", "capture_id" => match.capture_id, "bib" => bib }
            else { "kind" => "insert_capture", "bib" => bib, "at_ms" => mid }
            end
      Suggestion.new(key: "missed:#{bib}:#{seg.from_ref}:#{seg.to.ref}", kind: :suspected_missed_crossing, bib:, race_id:,
                     message: "Bib #{bib} lap #{seg.index} took #{fmt(seg.ms)}, about #{(seg.ms / ref).round(1)}× typical #{fmt(ref)} — missed crossing?",
                     fix:)
    end

    def lapping_suggestions
      @cohorts.reject(&:finish_open_at).flat_map do |cohort|
        racing = cohort.racers.select { it.status == :racing && it.counted.any? }
        leader = racing.min_by { [-it.counted.size, it.counted.last.at_ms, it.counted.last.ref] }
        next [] unless leader
        lead_ref = lap_ref(leader)
        racing.reject { it.equal?(leader) }.filter_map { lapping(leader, lead_ref, it) }
      end
    end

    def lap_ref(racer)
      segs = Anomalies.segments_for(racer)
      later = segs.select { it.index >= 2 }.map(&:ms)
      later.any? ? Anomalies.median(later) : segs.first.ms.to_f
    end

    # Projects both racers forward at their typical pace; flags the racer if the
    # leader gains another whole lap on them before their next crossing.
    def lapping(leader, lead_ref, racer)
      ref = lap_ref(racer)
      now = @input.now_ms
      next_crossing = racer.counted.last.at_ms + ref
      return nil if next_crossing < now || lead_ref <= 0 || ref <= 0
      position = ->(r, r_ref, t) { r.counted.size + (t - r.counted.last.at_ms) / r_ref }
      gap_now = position.(leader, lead_ref, now) - position.(racer, ref, now)
      gap_next = position.(leader, lead_ref, next_crossing) - (racer.counted.size + 1)
      return nil unless gap_next >= 1 && gap_next.floor > gap_now.floor
      bib = racer.entrant.bib
      Suggestion.new(key: "lapped:#{bib}:#{racer.counted.size}", kind: :about_to_be_lapped, bib:, race_id: racer.entrant.race_id,
                     message: "Bib #{bib} will likely be lapped by the leader before their next crossing",
                     fix: { "kind" => "flag_finish", "bib" => bib })
    end

    def clock_suggestions
      @resolved.unsynced_devices.map do |device|
        Suggestion.new(key: "clock:#{device}", kind: :unsynced_clock, bib: nil, race_id: nil,
                       message: "Device #{device} recorded captures before its clock was synced with the hub; their times are provisional",
                       fix: nil)
      end
    end

    def unassigned_suggestions
      @resolved.unassigned.map do |u|
        message = u.bib ? "Unknown racer: bib #{u.bib}" : "No bib"
        Suggestion.new(key: "unassigned:#{u.capture_id}", kind: :unassigned_capture, bib: u.bib, race_id: nil, message:,
                       fix: { "kind" => "assign_bib", "capture_id" => u.capture_id, "bib" => nil })
      end
    end

    def fmt(ms)
      seconds = (ms / 1000.0).round
      format("%d:%02d", seconds / 60, seconds % 60)
    end
  end
end
