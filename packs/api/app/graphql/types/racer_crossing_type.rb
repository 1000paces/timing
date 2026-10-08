module Types
  class RacerCrossingType < BaseObject
    field :ref, ID, null: false, description: "A capture id, or an insert_capture ruling id"
    field :at_ms, Millis, null: false
    field :inserted, Boolean, null: false
    field :kind, CrossingKindEnum, null: false
    field :lap, Integer
    field :lap_ms, Millis
    field :source, String, null: false, description: "The device's name, or 'inserted by <official>'"
  end
end
