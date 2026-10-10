# A crossing as the capture screen shows it. Its bib is the resolved one: an
# official's assign_bib ruling, else the device's later bib entry, else what was
# typed (the results engine's order). Its lap is how many captures that bib has
# (from every device) since its race's current start, up to and including this
# one. Raw taps, no debounce; voided (deleted) captures don't count. Results has
# the official count. Only finish-line captures (no checkpoint) are laps, and a
# course event has no laps at all: every capture's info there is NONE.
#
# Each lap after the first is compared with the race's typical lap (the median
# of its other laps after lap 1): roughly double is a suspected missed lap,
# otherwise long (a mechanical?) or very short (a double tap?).
class CaptureLaps
  Info = Data.define(:lap, :lap_ms, :typical_ms, :flag)
  NONE = Info.new(lap: nil, lap_ms: nil, typical_ms: nil, flag: nil)
  MISSED = 1.7..2.3
  LONG_ABOVE = 1.5
  SHORT_BELOW = 0.5
  MIN_LAPS = 3

  # Captures voided by an active void_capture ruling (reverts applied).
  def self.voided_ids(event)
    rulings = Ruling.where(event:, kind: %w[void_capture revert])
                    .map { Results::Ruling.new(id: it.id, kind: it.kind, payload: it.payload, created_at_ms: it.created_at_ms) }
    Results::ActiveRulings.new(rulings).of("void_capture").to_set { it.payload["capture_id"] } +
      CaptureVoid.where(event:).pluck(:capture_id)
  end

  # capture id => bib from the latest active assign_bib ruling (reverts applied).
  def self.assigned_bibs(event)
    rulings = Ruling.where(event:, kind: %w[assign_bib revert])
                    .map { Results::Ruling.new(id: it.id, kind: it.kind, payload: it.payload, created_at_ms: it.created_at_ms) }
    Results::ActiveRulings.new(rulings).latest_by("assign_bib") { it.payload["capture_id"] }.transform_values { it.payload["bib"].to_s }
  end

  def initialize(event)
    @voided = self.class.voided_ids(event)
    starts = StandingsService.report(event).output.races.to_h { [ it.race_id, it.start_at_ms ] }
    race_by_bib = event.registrations.pluck(:bib, :race_id).to_h
    @start_by_bib = race_by_bib.transform_values { starts[it] }.compact
    device_bibs = BibAssignment.where(event:).order(:device_seq).pluck(:capture_id, :bib).to_h
    assigned = self.class.assigned_bibs(event)
    @sources = {}
    @bibs = Capture.where(event:).pluck(:id, :bib).to_h do |id, bib|
      @sources[id] = assigned[id] ? :ruling : device_bibs[id] ? :device : :entered
      [ id, (assigned[id] || device_bibs[id] || bib).to_s.strip.presence ]
    end
    finish = Capture.where(event:, checkpoint_id: nil).where.not(id: @voided.to_a).order(:captured_at_ms, :id)
    captures = (event.course? ? [] : finish.pluck(:id, :captured_at_ms))
               .filter_map { |id, at| (bib = @bibs[id]) && @start_by_bib.key?(bib) && [ bib, at, id ] }
    @info = {}
    laps_by_race = Hash.new { |h, k| h[k] = [] }
    captures.group_by(&:first).each do |bib, rows|
      start = @start_by_bib[bib]
      previous = start
      rows.select { |_, at, _| at >= start }.each.with_index(1) do |(_, at, id), lap|
        @info[id] = [ race_by_bib[bib], lap, at - previous ]
        laps_by_race[race_by_bib[bib]] << [ id, at - previous ] if lap > 1
        previous = at
      end
    end
    @laps_by_race = laps_by_race
  end

  def lap(capture) = info(capture).lap

  def bib(capture) = @bibs.fetch(capture.id) { capture.bib }

  # Where the shown bib comes from: :ruling (an official), :device (a later entry) or :entered.
  def bib_source(capture) = @sources.fetch(capture.id, :entered)

  def voided?(capture) = @voided.include?(capture.id)

  def info(capture)
    race_id, lap, lap_ms = @info[capture.id]
    return NONE unless lap
    return Info.new(lap:, lap_ms:, typical_ms: nil, flag: nil) if lap == 1
    others = @laps_by_race[race_id].filter_map { |id, ms| ms unless id == capture.id }
    typical = others.size >= MIN_LAPS ? median(others) : nil
    Info.new(lap:, lap_ms:, typical_ms: typical, flag: typical && flag(lap_ms.fdiv(typical)))
  end

  private

  def flag(ratio)
    if MISSED.cover?(ratio) then "missed"
    elsif ratio > LONG_ABOVE then "long"
    elsif ratio < SHORT_BELOW then "short"
    end
  end

  def median(values)
    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
  end
end
