module Types
  class RowMessageType < BaseObject
    field :row, Integer, null: false
    field :message, String, null: false
  end
end
