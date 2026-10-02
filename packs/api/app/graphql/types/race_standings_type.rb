module Types
  # object: { result: Results::RaceResult, race: Race }
  class RaceStandingsType < BaseObject
    field :race, RaceType, null: false
    field :state, RaceStateEnum, null: false
    field :lap_count, Integer
    field :publication, PublicationEnum, null: false
    field :digest, String, null: false
    field :rows, [StandingRowType], null: false

    def race = object[:race]
    def state = object[:result].state
    def lap_count = object[:result].lap_count
    def publication = object[:result].publication
    def digest = object[:result].digest
    def rows = object[:result].rows
  end
end
