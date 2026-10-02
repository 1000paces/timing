module Types
  class SubDisciplineType < BaseObject
    field :id, String, null: false
    field :label, String, null: false
    field :finish_with_leader, Boolean, null: false
  end
end
