module Types
  class RaceType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false, description: "The override if set, else the default name"
    field :default_name, String, null: false, description: "Category + age group + gender"
    field :name_override, String
    field :category, String
    field :age_group, String
    field :age_min, Integer
    field :age_max, Integer
    field :gender, String, null: false
    field :scheduled_at_ms, Millis, null: false
    field :expected_duration_ms, Millis
    field :expected_laps, Integer
    field :finish_with_leader, Boolean, null: false, description: "Effective: the override, else the event's"
    field :finish_with_leader_override, Boolean
    field :bib_from, Integer
    field :bib_to, Integer

    def finish_with_leader = object.effective_finish_with_leader
    def finish_with_leader_override = object.finish_with_leader
  end
end
