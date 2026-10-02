module Types
  class RegistrationType < BaseObject
    field :id, ID, null: false
    field :bib, String, null: false
    field :race_id, ID, null: false
    field :rider, RiderType, null: false
    field :eligibility_warnings, [String], null: false

    def eligibility_warnings
      context[:current_official]&.at_least?("chief") ? object.eligibility_warnings : []
    end
  end
end
