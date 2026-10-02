module Types
  class StartGroupType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :scheduled_at_ms, Millis
    field :finish_rule, GraphQL::Types::JSON, null: false
    field :races, [RaceType], null: false

    def races = object.races.includes(:category).order(:id)
  end
end
