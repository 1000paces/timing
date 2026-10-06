module Types
  class RegistrationType < BaseObject
    field :id, ID, null: false
    field :bib, String, description: "Null until one is given out"
    field :race_id, ID, null: false
    field :race, RaceType, null: false
    field :age, Integer, description: "Age for this event as reported by the import (used when the birth date is unknown)"
    field :source, String, null: false, description: "import or manual"
    field :external_category, String, description: "The category text from the imported file"
    field :checked_in_at_ms, Millis
    field :rider, RiderType, null: false
    field :eligibility_warnings, [String], null: false

    def eligibility_warnings
      context[:current_official]&.at_least?("chief") ? object.eligibility_warnings : []
    end
  end
end
