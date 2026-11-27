module Types
  class CheckpointInput < BaseInputObject
    argument :id, ID, required: false, description: "An existing checkpoint to keep (omit for a new one)"
    argument :name, String
    argument :distance_km, Float, required: false
    argument :cutoff_at_ms, Millis, required: false
  end
end
