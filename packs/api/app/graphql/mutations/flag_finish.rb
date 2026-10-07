module Mutations
  class FlagFinish < RulingMutation
    include OfficiatingFix
    description "Make one of the racer's crossings their finish (early checkered flag)"
    argument :event_id, ID
    argument :bib, String
    argument :ref, String

    def resolve(event_id:, bib:, ref:)
      require_official!("chief")
      event = Event.find(event_id)
      bib = bib.strip
      refusal = registered!(event, bib)
      return refusal if refusal
      _, row = racer_row(event, bib)
      return refuse("That crossing isn't one of bib #{bib}'s") unless row&.crossings&.any? { it.ref == ref }
      record(event:, kind: "flag_finish", payload: { bib:, capture_id: ref })
    end
  end
end
