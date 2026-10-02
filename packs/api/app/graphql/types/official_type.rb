module Types
  class OfficialType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :role, String, null: false
  end
end
