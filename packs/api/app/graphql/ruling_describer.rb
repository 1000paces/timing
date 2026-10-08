# One readable line per ruling, for History and the racer panel, with times in
# the event's time zone: "Void crossing 10:42:09 (bib 101)".
class RulingDescriber
  # Everything it reads is loaded once up front, so describing hundreds of
  # rulings costs the same few queries as describing one.
  def initialize(event, rulings: Ruling.where(event:).to_a)
    @event = event
    @zone = ActiveSupport::TimeZone[event.timezone] || Time.zone
    @rulings = rulings.index_by(&:id)
    @captures = Capture.where(event:).pluck(:id, :bib, :captured_at_ms, :clock_offset_ms).to_h { |id, *rest| [id, rest] }
    @device_bibs = BibAssignment.where(event:).order(:device_seq).pluck(:capture_id, :bib).to_h
    @moved_bibs = CaptureLaps.assigned_bibs(event)
  end

  def describe(ruling)
    p = ruling.payload
    case ruling.kind
    when "void_capture" then "Void crossing #{crossing_time(p['capture_id'])} (bib #{current_bib(p['capture_id']) || 'no bib'})"
    when "assign_bib" then "Bib #{entered_bib(p['capture_id'])} → #{p['bib']} for crossing #{crossing_time(p['capture_id'])}"
    when "insert_capture" then "Insert crossing #{clock(p['at_ms'])} for bib #{p['bib']}"
    when "pull" then "Pull bib #{p['bib']} at #{clock(p['at_ms'])}"
    when "flag_finish" then "Finish bib #{p['bib']} at #{crossing_time(p['capture_id'])}"
    when "dnf", "dns", "dsq" then "#{ruling.kind.upcase} bib #{p['bib']}"
    when "set_lap_count" then "Lap count #{p['laps']} for #{race_name(p['race_id'])}"
    when "flag_out" then "Flag out for #{race_name(p['race_id'])}'s wave at #{clock(p['at_ms'])}"
    when "set_race_start" then "Start #{race_name(p['race_id'])} at #{clock(p['at_ms'])}"
    when "dismiss_suggestion" then "Dismiss a suggestion"
    when "publish_results" then "Publish #{race_name(p['race_id'])}"
    when "revert" then "Undo: #{(target = find_ruling(p['ruling_id'])) ? describe(target) : 'a fix'}"
    else ruling.kind.tr("_", " ").capitalize
    end
  end

  # The racer a ruling links to: a move links to the bib it moved the crossing to.
  def bib_for(ruling)
    target = ruling.kind == "revert" ? find_ruling(ruling.payload["ruling_id"]) : ruling
    return unless target
    target.kind == "assign_bib" ? target.payload["bib"].to_s : bibs_for(target).first
  end

  # Every bib a ruling concerns (for search and a racer's fixes): its own bib, the
  # bib its crossing carries, and for a move both the old bib and the new one.
  def bibs_for(ruling)
    p = ruling.payload
    return (target = find_ruling(p["ruling_id"])) ? bibs_for(target) : [] if ruling.kind == "revert"
    ref = p["capture_id"]
    [p["bib"].presence&.to_s, ref && entered_bib(ref), ref && current_bib(ref)].compact.uniq - ["no bib"]
  end

  private

  def clock(ms) = ms ? Time.at(ms / 1000.0).in_time_zone(@zone).strftime("%H:%M:%S") : "?"

  def crossing_time(ref)
    if (c = @captures[ref]) then clock(c[1] + c[2].to_i)
    elsif (insert = find_ruling(ref)) then clock(insert.payload["at_ms"])
    else "?"
    end
  end

  # The bib a crossing came in with: the phone's later entry, else what was typed
  # (or an inserted crossing's bib).
  def entered_bib(ref)
    bib = @captures.key?(ref) ? (@device_bibs[ref] || @captures[ref][0]) : find_ruling(ref)&.payload&.dig("bib")
    bib.to_s.strip.presence || "no bib"
  end

  # The bib the crossing counts for now: an official's move, else as entered.
  def current_bib(ref) = @moved_bibs[ref] || entered_bib(ref).then { it == "no bib" ? nil : it }

  def race_name(id) = (@races ||= @event.races.index_by(&:id))[id]&.name || "a race"

  def find_ruling(id) = @rulings[id]
end
