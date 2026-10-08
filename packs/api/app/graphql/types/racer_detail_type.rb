module Types
  class RacerDetailType < BaseObject
    field :bib, String, null: false
    field :name, String, null: false
    field :race, RaceType, null: false
    field :status, RacerStatusEnum, null: false
    field :place, Integer
    field :laps, Integer, null: false
    field :elapsed_ms, Millis
    field :gap_laps_down, Integer
    field :gap_ms, Millis
    field :start_at_ms, Millis
    field :pull_at_ms, Millis
    field :finish_ref, ID
    field :lap_positions, [Integer], null: false
    field :crossings, [RacerCrossingType], null: false
    field :rulings, [RacerRulingType], null: false, description: "Fixes affecting this racer, newest first"
  end
end
