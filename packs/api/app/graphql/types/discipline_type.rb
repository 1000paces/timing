module Types
  class DisciplineType < BaseObject
    field :id, String, null: false
    field :label, String, null: false
    field :finish_with_leader, Boolean, null: false
    field :sub_disciplines, [SubDisciplineType], null: false

    def sub_disciplines = object.subs
  end
end
