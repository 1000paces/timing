module Types
  class CheckpointType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :position, Integer, null: false, description: "1 is the first after the start; the finish is always after the last"
    field :distance_km, Float
    field :cutoff_at_ms, Millis, description: "Clock time riders must reach it by, or null"

    def distance_km = object.distance_km&.to_f
  end
end
