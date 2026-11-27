module Types
  class SplitType < BaseObject
    field :checkpoint_id, ID, description: "Null for the finish"
    field :at_ms, Millis, description: "Null when the racer has no crossing there"
    field :elapsed_ms, Millis
    field :segment_ms, Millis, description: "Since the previous checkpoint they were seen at (or the start)"
    field :inserted, Boolean, null: false
  end
end
