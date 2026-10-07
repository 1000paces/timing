module Types
  class RacerRulingType < BaseObject
    field :id, ID, null: false
    field :kind, String, null: false
    field :description, String, null: false
    field :bib, String
    field :official_name, String
    field :created_at_ms, Millis, null: false
    field :undone, Boolean, null: false
    field :undone_by, String
    field :undone_at_ms, Millis
  end
end
