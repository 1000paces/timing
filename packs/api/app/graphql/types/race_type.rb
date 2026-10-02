module Types
  class RaceType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :start_offset_ms, Millis, null: false
    field :start_group_id, ID, null: false
    field :category, CategoryType, null: false
  end
end
