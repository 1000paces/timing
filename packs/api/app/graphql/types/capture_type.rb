module Types
  class CaptureType < BaseObject
    field :id, ID, null: false
    field :bib, String
    field :captured_at_ms, Millis, null: false
  end
end
