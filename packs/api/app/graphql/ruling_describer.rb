# One readable line per ruling, for History and the racer panel, with times in
# the event's time zone: "Void crossing 10:42:09 (bib 101)".
class RulingDescriber
  def initialize(event)
    @event = event
    @zone = ActiveSupport::TimeZone[event.timezone] || Time.zone
    @rulings = {}
  end

  def describe(ruling)
    p = ruling.payload
    case ruling.kind
    when "void_capture" then "Void crossing #{crossing_time(p['capture_id'])} (bib #{entered_bib(p['capture_id'])})"
    when "assign_bib" then "Bib #{entered_bib(p['capture_id'])} → #{p['bib']} for crossing #{crossing_time(p['capture_id'])}"
    when "insert_capture" then "Insert crossing #{clock(p['at_ms'])} for bib #{p['bib']}"
    when "pull" then "Pull bib #{p['bib']} at #{clock(p['at_ms'])}"
    when "flag_finish" then "Finish bib #{p['bib']} at #{crossing_time(p['capture_id'])}"
    when "dnf", "dns", "dsq" then "#{ruling.kind.upcase} bib #{p['bib']}"
    when "set_lap_count" then "Lap count #{p['laps']} for #{race_name(p['race_id'])}"
    when "set_race_start" then "Start #{race_name(p['race_id'])} at #{clock(p['at_ms'])}"
    when "dismiss_suggestion" then "Dismiss a suggestion"
    when "publish_results" then "Publish #{race_name(p['race_id'])}"
    when "revert" then "Undo: #{(target = find_ruling(p['ruling_id'])) ? describe(target) : 'a fix'}"
    else ruling.kind.tr("_", " ").capitalize
    end
  end

  # The bib a ruling concerns, if any (for search and the racer link).
  def bib_for(ruling)
    p = ruling.payload
    return describe_target_bib(p["ruling_id"]) if ruling.kind == "revert"
    return p["bib"].to_s if p["bib"].present? && ruling.kind != "assign_bib"
    entered_bib(p["capture_id"]).then { it == "no bib" ? nil : it } if p["capture_id"]
  end

  private

  def describe_target_bib(id) = (target = find_ruling(id)) && bib_for(target)

  def clock(ms) = ms ? Time.at(ms / 1000.0).in_time_zone(@zone).strftime("%H:%M:%S") : "?"

  def capture(id) = (@captures ||= {})[id] ||= Capture.find_by(id:, event: @event)

  def crossing_time(ref)
    if (c = capture(ref)) then clock(c.captured_at_ms + c.clock_offset_ms.to_i)
    elsif (insert = find_ruling(ref)) then clock(insert.payload["at_ms"])
    else "?"
    end
  end

  def entered_bib(ref) = capture(ref)&.bib || find_ruling(ref)&.payload&.dig("bib") || "no bib"

  def race_name(id) = (@races ||= @event.races.index_by(&:id))[id]&.name || "a race"

  def find_ruling(id) = @rulings.fetch(id) { @rulings[id] = Ruling.find_by(id:, event: @event) }
end
