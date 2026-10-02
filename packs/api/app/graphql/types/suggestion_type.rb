module Types
  class SuggestionType < BaseObject
    field :key, String, null: false
    field :kind, SuggestionKindEnum, null: false
    field :bib, String
    field :race_id, ID
    field :message, String, null: false
    field :fix, GraphQL::Types::JSON, description: "Ruling template; see needs"
    field :needs, [String], null: false, description: "Payload fields an official must supply before accepting"

    def needs = SuggestionFix.missing(object.fix)
  end
end
