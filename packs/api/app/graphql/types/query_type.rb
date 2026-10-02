module Types
  class QueryType < BaseObject
    field :me, OfficialType, description: "The signed-in official, or null"
    field :events, [EventType], null: false
    field :event, EventType, null: false do
      argument :id, ID
    end
    field :categories, [CategoryType], null: false

    def me = context[:current_official]

    def events
      require_official!
      Event.order(date: :desc, name: :asc)
    end

    def event(id:)
      require_official!
      Event.find(id)
    end

    def categories
      require_official!
      Category.order(:name)
    end
  end
end
