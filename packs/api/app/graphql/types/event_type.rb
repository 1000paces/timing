module Types
  class EventType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :date, GraphQL::Types::ISO8601Date, null: false
    field :location, String
    field :discipline, String, null: false
    field :sub_discipline, String
    field :finish_with_leader, Boolean, null: false, description: "Default for races that don't override it"
    field :timezone, String, null: false
    field :age_rule, String, null: false
    field :races, [RaceType], null: false, description: "In scheduled order, then name"
    field :registrations, [RegistrationType], null: false

    def races = object.races.to_a.sort_by { [it.scheduled_at_ms, it.name] }
    def registrations = object.registrations.includes(:event, :rider, :race).order(:bib)
  end
end
