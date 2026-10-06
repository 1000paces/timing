module Types
  class StandingRowType < BaseObject
    field :place, Integer
    field :bib, String, null: false
    field :name, String, null: false
    field :status, RacerStatusEnum, null: false
    field :laps, Integer, null: false
    field :elapsed_ms, Millis
    field :gap_laps_down, Integer
    field :gap_ms, Millis
    field :lap_times_ms, [Millis], null: false

    def gap_laps_down = object.gap&.laps_down
    def gap_ms = object.gap&.ms
  end
end
