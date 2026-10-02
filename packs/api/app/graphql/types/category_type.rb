module Types
  class CategoryType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :gender, String, null: false
    field :ability_levels, [String], null: false
    field :age_min, Integer
    field :age_max, Integer
  end
end
