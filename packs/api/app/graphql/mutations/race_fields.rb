module Mutations
  # Arguments shared by createRace and updateRace.
  module RaceFields
    def self.included(mutation)
      mutation.argument :category, String, required: false
      mutation.argument :age_group, String, required: false
      mutation.argument :age_min, Integer, required: false
      mutation.argument :age_max, Integer, required: false
      mutation.argument :name_override, String, required: false, description: "Blank or null uses the default name"
      mutation.argument :expected_duration_ms, Types::Millis, required: false
      mutation.argument :expected_laps, Integer, required: false
      mutation.argument :finish_with_leader, GraphQL::Types::Boolean, required: false, description: "Null inherits the event's setting"
      mutation.argument :bib_from, Integer, required: false
      mutation.argument :bib_to, Integer, required: false
      mutation.field :race, Types::RaceType
    end
  end
end
