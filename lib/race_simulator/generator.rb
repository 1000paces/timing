module RaceSimulator
  # Ground-truth crossings for a start group. Each racer has a pace within
  # ±spread of lap_ms, laps vary by ±jitter, and the start lap is shorter.
  # Racers stop on their first crossing after the leader completes `laps`.
  class Generator
    def initialize(races:, laps:, seed: 1, lap_ms: 300_000, spread: 0.12, jitter: 0.03, start_lap_factor: 0.8,
                   untagged_rate: 0.0, untagged_min_gap_ms: 120_000)
      @races = races
      @laps = laps
      @seed = seed
      @lap_ms = lap_ms
      @spread = spread
      @jitter = jitter
      @start_lap_factor = start_lap_factor
      @untagged_rate = untagged_rate
      @untagged_min_gap_ms = untagged_min_gap_ms
    end

    def call
      rng = Random.new(@seed)
      raw = @races.flat_map do |race|
        race.bibs.map do |bib|
          pace = @lap_ms * (1 + rng.rand(-@spread..@spread))
          t = race.offset_ms
          crossings = Array.new(@laps + 3) do |i|
            t += (pace * (i.zero? ? @start_lap_factor : 1) * (1 + rng.rand(-@jitter..@jitter))).round
          end
          [ bib.to_s, race.race_id, crossings ]
        end
      end
      leader_finish = raw.map { |_, _, crossings| crossings[@laps - 1] }.min
      truths = raw.map do |bib, race_id, crossings|
        RacerTruth.new(bib:, race_id:, crossings_ms: crossings[0..crossings.index { it >= leader_finish }], untagged: [])
      end
      pick_untagged(truths, rng)
    end

    private

    # At most one bib-less tap per racer, never the first or last crossing, and
    # far enough apart that each lines up with only one racer's missed crossing.
    def pick_untagged(truths, rng)
      taken = []
      truths.sort_by(&:bib).to_h do |truth|
        candidates = (1..truth.crossings_ms.size - 2).to_a
        pick = nil
        if candidates.any? && rng.rand < @untagged_rate
          index = candidates[rng.rand(candidates.size)]
          at = truth.crossings_ms[index]
          if taken.all? { (it - at).abs >= @untagged_min_gap_ms }
            taken << at
            pick = index
          end
        end
        [ truth.bib, truth.with(untagged: pick ? [ pick ] : []) ]
      end.then { |by_bib| truths.map { by_bib.fetch(it.bib) } }
    end
  end
end
