module Types
  class BibAssignmentType < BaseObject
    field :bib, String, null: false
    field :name, String, null: false
    field :race_name, String, null: false
  end
end
