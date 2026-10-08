# Computes an event's standings for the API. If the engine raises, officials keep
# seeing the last good standings, marked stale, instead of an error page (spec §9).
class StandingsService
  Report = Data.define(:event, :output, :computed_at_ms, :stale, :error)
  EMPTY = Results::Output.new(races: [], suggestions: [], unassigned: [])
  LAST_GOOD = Concurrent::Map.new

  def self.report(event, now_ms: Clock.now_ms, compute: ResultsSnapshot.method(:compute))
    output = compute.call(event, now_ms:)
    LAST_GOOD[event.id] = [ output, now_ms ]
    Report.new(event:, output:, computed_at_ms: now_ms, stale: false, error: nil)
  rescue StandardError => e
    Rails.logger.error("[standings] event #{event.id}: #{e.class}: #{e.message}\n#{Array(e.backtrace).first(10).join("\n")}")
    output, at = LAST_GOOD[event.id]
    Report.new(event:, output: output || EMPTY, computed_at_ms: at, stale: true, error: "#{e.class}: #{e.message}")
  end
end
