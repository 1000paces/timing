module Types
  class ImportCategoryType < BaseObject
    field :value, String, null: false, description: "The category text in the file"
    field :count, Integer, null: false
    field :race_id, ID, description: "Suggested race: the saved choice, else a race of the same name"
    field :skip, Boolean, null: false
  end
end
