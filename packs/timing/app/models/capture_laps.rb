# A crossing's lap as the capture screen shows it: how many captures that bib
# has (from every device) since its race's current start, up to and including
# this one. Raw taps, no debounce or rulings — Results has the official count.
class CaptureLaps
  def initialize(event)
    starts = StandingsService.report(event).output.races.to_h { [it.race_id, it.start_at_ms] }
    @start_by_bib = event.registrations.pluck(:bib, :race_id).to_h { |bib, race_id| [bib, starts[race_id]] }.compact
    @times_by_bib = Capture.where(event:, bib: @start_by_bib.keys).order(:captured_at_ms, :id)
                           .pluck(:bib, :captured_at_ms, :id).group_by(&:first)
  end

  def lap(capture)
    start = @start_by_bib[capture.bib]
    return nil if start.nil? || capture.captured_at_ms < start
    key = [capture.captured_at_ms, capture.id]
    @times_by_bib.fetch(capture.bib, []).count { |_, at, id| at >= start && ([at, id] <=> key) <= 0 }
  end
end
