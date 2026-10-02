module RaceSimulator
  # Writes taps in time order; with speed > 0 it waits so the race plays out
  # `speed` times faster than real time (speed 0 writes everything at once).
  class Runner
    Tap = Data.define(:at_ms, :bib)

    def self.taps(truths)
      truths.flat_map do |truth|
        truth.crossings_ms.each_with_index.map { |ms, i| Tap.new(at_ms: ms, bib: truth.untagged.include?(i) ? nil : truth.bib) }
      end.sort_by { [it.at_ms, it.bib.to_s] }
    end

    def initialize(writer:, gun_at_ms:, truths:, speed: 0, sleeper: ->(seconds) { sleep(seconds) })
      @writer = writer
      @gun_at_ms = gun_at_ms
      @truths = truths
      @speed = speed
      @sleeper = sleeper
    end

    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      self.class.taps(@truths).each do |tap|
        if @speed.positive?
          wait = tap.at_ms / 1000.0 / @speed - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
          @sleeper.call(wait) if wait.positive?
        end
        @writer.capture(at_ms: @gun_at_ms + tap.at_ms, bib: tap.bib)
      end
    end
  end
end
