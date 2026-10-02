module Types
  class UnassignedCaptureType < BaseObject
    field :capture_id, ID, null: false
    field :at_ms, Millis, null: false
    field :bib, String
  end
end
