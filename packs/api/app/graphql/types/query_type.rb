module Types
  class QueryType < BaseObject
    field :me, OfficialType, description: "The signed-in official, or null"
    field :events, [EventType], null: false
    field :event, EventType, null: false do
      argument :id, ID
    end
    field :categories, [CategoryType], null: false
    field :officials, [OfficialType], null: false
    field :standings, StandingsReportType, null: false do
      argument :event_id, ID
    end

    def me = context[:current_official]

    def events
      require_official!
      Event.order(date: :desc, name: :asc)
    end

    def event(id:)
      require_official!
      Event.find(id)
    end

    def officials
      require_official!("admin")
      Official.order(:name)
    end

    def standings(event_id:)
      require_official!
      StandingsService.report(Event.find(event_id))
    end

    def categories
      require_official!
      Category.order(:name)
    end
  end
end
