module Mutations
  class AcceptSuggestion < RulingMutation
    argument :event_id, ID
    argument :key, String
    argument :capture_id, ID, required: false
    argument :bib, String, required: false

    def resolve(event_id:, key:, capture_id: nil, bib: nil)
      require_official!("chief")
      event = Event.find(event_id)
      suggestion = StandingsService.report(event).output.suggestions.find { it.key == key }
      return refuse("That suggestion is no longer open; it may already have been handled") unless suggestion
      return refuse("This suggestion has no automatic fix; record a ruling instead") unless suggestion.fix
      fix = SuggestionFix.complete(suggestion.fix, capture_id:, bib:)
      missing = SuggestionFix.missing(fix)
      return refuse("Provide #{missing.join(' and ')} to accept this suggestion") if missing.any?
      record(event:, kind: fix["kind"], payload: fix.except("kind"))
    end
  end
end
