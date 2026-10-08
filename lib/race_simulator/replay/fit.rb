module RaceSimulator
  module Replay
    # Estimates what a results file doesn't say, wave by wave:
    # - start_s: later starts in a wave have a smaller first-lap shortfall (lap 1
    #   is timed from the wave's arming), rounded to 30 s;
    # - arm_s: the biggest shortfall in the wave, rounded to 15 s;
    # - flag_out_s: the moment between the last rider who rode on and the first
    #   who stopped, with the leader riding on to the lap count.
    class Fit
      def initialize(dataset) = @dataset = dataset

      def waves
        @dataset.waves.map do |wave|
          shortfalls = wave.races.to_h { [it.name, shortfall(@dataset.results_for([it.name]))] }
          top = shortfalls.values.compact.max || 0
          arm_s = (top / 15.0).round * 15
          races = wave.races.map do |race|
            short = shortfalls[race.name]
            race.with(start_s: short ? [arm_s, ((top - short) / 30.0).round * 30].min : 0)
          end
          wave.with(arm_s:, races: races.sort_by { [it.start_s, -(shortfalls[it.name] || 0)] }, flag_out_s: flag_out_s(wave))
        end
      end

      def to_yaml
        lines = ["waves:"]
        waves.each do |w|
          lines += [%(  - gun: "#{w.gun}"), "    minutes: #{w.minutes}", "    arm_s: #{w.arm_s}"]
          lines << "    flag_out_s: #{w.flag_out_s}" if w.flag_out_s
          lines << "    races:"
          w.races.each do |r|
            lines << %(      - { name: "#{r.name}", start_s: #{r.start_s}#{', finish_with_leader: false' unless r.finish_with_leader} })
          end
        end
        lines.join("\n") + "\n"
      end

      private

      # Seconds lap 1 is short of lap 2: the median and the leader's, averaged.
      def shortfall(results)
        gaps = results.filter_map { (it.laps_ms[1] - it.laps_ms[0]) / 1000.0 if it.laps >= 2 }
        return nil if gaps.empty?
        sorted = gaps.sort
        median = sorted.size.odd? ? sorted[sorted.size / 2] : (sorted[sorted.size / 2 - 1] + sorted[sorted.size / 2]) / 2
        (median + gaps.first) / 2
      end

      # Seconds after arming, or nil when the wave's lap count explains everyone.
      def flag_out_s(wave)
        results = @dataset.results_for(wave.cohorts.first.map(&:name))
        crossings = results.to_h { |r| [r, r.laps_ms.each_with_object([]) { |ms, at| at << (at.last || 0) + ms }] }
        laps = wave.lap_count(results)
        leader = crossings.min_by { |_, at| [-at.size, at[laps - 1] || Float::INFINITY] }.first
        misfits = lambda do |flag|
          # A rider who never crosses after the flag stays racing: a misfit too.
          crossings.count { |r, at| r != leader && ((i = at.index { it >= flag }).nil? || i + 1 != r.laps) }
        end
        times = crossings.values.flatten.uniq.sort
        best = times.min_by { |t| [misfits.(t), t] }
        before = times.select { it < best }.max || 0
        return nil if best >= crossings[leader].fetch(laps - 1) # the leader's finish opens it anyway
        ((before + best) / 2000.0).round
      end
    end
  end
end
