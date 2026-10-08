module RaceSimulator
  module Replay
    # Compares the hub's standings for a replayed event with the real results.
    # The real lap 1 runs from when the wave was armed; ours from the race's
    # start, so our lap 1 is longer by (arm_s - start_s). Everything else —
    # finished, place, laps, laps 2 on — should match exactly — except riders
    # who quit before the flag came out: the hub keeps them "racing" until an
    # official marks them DNF, so those are listed apart.
    class Check
      Difference = Data.define(:race, :bib, :what, :ours, :theirs) do
        def to_s = "#{race} ##{bib}: #{what} ours #{ours}, theirs #{theirs}"
        def stopped_early? = what == "status" && ours.to_s == "racing"
      end

      def initialize(event:, dataset:, now_ms: nil)
        @event = event
        @dataset = dataset
        @now_ms = now_ms || (Capture.where(event:).maximum(:captured_at_ms).to_i + 3_600_000)
      end

      def races_checked = results.size

      def differences
        @differences ||= results.flat_map do |name, rows|
          start = @dataset.races.find { it.name == name }
          shift_ms = (@dataset.wave_of(name).arm_s - start.start_s) * 1000
          @dataset.results_for([name]).flat_map { compare(name, it, rows[it.bib], shift_ms) }
        end
      end

      def stopped_early = differences.select(&:stopped_early?)
      def mismatches = differences.reject(&:stopped_early?)

      def report
        lines = results.keys.map do |name|
          found = mismatches.select { it.race == name }
          early = stopped_early.select { it.race == name }.map(&:bib)
          [found.empty? ? "✓ #{name}" : "✗ #{name}", *found.map { "    #{it}" },
           *("    quit before the flag (an official marks them DNF): #{early.join(', ')}" if early.any?)]
        end
        [*lines.flatten, "",
         "#{races_checked} races: #{mismatches.size} mismatch#{'es' unless mismatches.size == 1}, " \
         "#{stopped_early.size} riders quit before the flag"].join("\n")
      end

      private

      # race name => { bib => RacerResult }
      def results
        @results ||= begin
          names = @event.races.to_h { [it.id, it.name] }
          StandingsService.report(@event, now_ms: @now_ms).output.races
                          .to_h { [names.fetch(it.race_id), it.rows.index_by(&:bib)] }
                          .sort_by { |name, _| @dataset.races.index { it.name == name } }.to_h
        end
      end

      def compare(race, theirs, ours, shift_ms)
        diff = ->(what, mine, real) { Difference.new(race:, bib: theirs.bib, what:, ours: mine, theirs: real) }
        return [diff.("result", "missing", "place #{theirs.place}")] unless ours

        found = []
        found << diff.("status", ours.status, "finished") unless ours.status.to_s == "finished"
        found << diff.("place", ours.place.inspect, theirs.place) unless ours.place == theirs.place
        found << diff.("laps", ours.laps, theirs.laps) unless ours.laps == theirs.laps
        expected = theirs.laps_ms.each_with_index.map { |ms, i| i.zero? ? ms + shift_ms : ms }
        lap = expected.zip(ours.lap_times_ms).index { |want, got| want != got }
        found << diff.("lap #{lap + 1}", Table.clock(ours.lap_times_ms[lap]), Table.clock(expected[lap])) if lap && lap < ours.laps
        found
      end
    end
  end
end
