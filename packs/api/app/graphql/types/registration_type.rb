module Types
  class RegistrationType < BaseObject
    field :id, ID, null: false
    field :bib, String, description: "Null until one is given out"
    field :race_id, ID, null: false
    field :race, RaceType, null: false
    field :age, Integer, description: "Age entered or imported for this event"
    field :racing_age, Integer, description: "The age entered, else worked out from the birth date by the event's age rule"
    field :source, String, null: false, description: "import or manual"
    field :external_category, String, description: "The category text from the imported file"
    field :checked_in_at_ms, Millis
    field :official_status, String, description: "DNF, DNS or DSQ when an official has marked the racer; else null"
    field :racer, RacerType, null: false
    field :eligibility_warnings, [ String ], null: false

    # One lookup per event per request, shared by every registration in the list.
    def official_status = ((context[:racer_statuses] ||= {})[object.event_id] ||= RacerStatuses.by_bib(object.event))[object.bib]

    def eligibility_warnings
      context[:current_official]&.at_least?("chief") ? object.eligibility_warnings : []
    end
  end
end
