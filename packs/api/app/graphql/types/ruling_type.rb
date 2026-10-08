module Types
  class RulingType < BaseObject
    field :id, ID, null: false
    field :kind, String, null: false
    field :payload, GraphQL::Types::JSON, null: false
    field :reason, String
    field :created_at_ms, Millis, null: false
    field :official_name, String
    field :reverted, Boolean, null: false, description: "Same as undone"
    field :description, String, null: false, description: "One readable line, times in the event's time zone"
    field :bib, String, description: "The racer it concerns, if any"
    field :undone, Boolean, null: false
    field :undone_by, String
    field :undone_at_ms, Millis

    def official_name = entry[:official_name]
    def reverted = entry[:undone]
    def description = entry[:description]
    def bib = entry[:bib]
    def undone = entry[:undone]
    def undone_by = entry[:undone_by]
    def undone_at_ms = entry[:undone_at_ms]

    private

    def entry
      @entry ||= (context[:ruling_history] ||= RulingHistory.new(object.event)).entry(object)
    end
  end
end
