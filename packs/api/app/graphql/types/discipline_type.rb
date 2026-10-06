module Types
  class DisciplineType < BaseObject
    field :id, String, null: false
    field :label, String, null: false
    field :finish_with_leader, Boolean, null: false
    field :age_next_year, Boolean, null: false, description: "Default for events: racing age as of the end of the following year"
    field :sub_disciplines, [SubDisciplineType], null: false

    def sub_disciplines = object.subs
  end
end
