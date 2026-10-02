# Suggestion fixes are ruling templates; some need an official to fill a blank
# (the bib for an unassigned capture, the crossing for an early flag).
module SuggestionFix
  module_function

  def missing(fix)
    return [] unless fix
    blanks = fix.select { |_key, value| value.nil? }.keys
    blanks << "capture_id" if fix["kind"] == "flag_finish" && !fix.key?("capture_id")
    blanks
  end

  def complete(fix, capture_id: nil, bib: nil)
    filled = fix.dup
    filled["capture_id"] = capture_id if capture_id && (filled["capture_id"].nil? || !filled.key?("capture_id"))
    filled["bib"] = bib if bib && filled.key?("bib") && filled["bib"].nil?
    filled
  end
end
