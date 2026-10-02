module Types
  class EventType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :date, GraphQL::Types::ISO8601Date, null: false
    field :venue, String
    field :timezone, String, null: false
    field :age_rule, String, null: false
    field :start_groups, [StartGroupType], null: false
    field :races, [RaceType], null: false
    field :registrations, [RegistrationType], null: false

    def start_groups = object.start_groups.order(:scheduled_at_ms, :name, :id)
    def registrations = object.registrations.includes(:event, :rider, race: :category).order(:bib)
    def races = object.races.includes(:category).order(:start_offset_ms, :id)
  end
end
