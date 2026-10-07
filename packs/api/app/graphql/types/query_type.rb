module Types
  class QueryType < BaseObject
    field :me, OfficialType, description: "The signed-in official, or null"
    field :events, [EventType], null: false
    field :event, EventType, null: false do
      argument :id, ID
    end
    field :disciplines, [DisciplineType], null: false, description: "Disciplines, sub-disciplines and finish-with-leader defaults"
    field :officials, [OfficialType], null: false
    field :standings, StandingsReportType, null: false do
      argument :event_id, ID
    end

    field :rulings, [RulingType], null: false, description: "Newest first" do
      argument :event_id, ID
    end

    field :racer, RacerDetailType, description: "One racer's race: crossings, lap positions, fixes" do
      argument :event_id, ID
      argument :bib, String
    end
    field :devices, [DeviceType], null: false do
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

    def rulings(event_id:)
      require_official!
      rulings = Ruling.where(event_id:).order(created_at_ms: :desc, id: :desc).to_a
      engine_rulings = rulings.map { Results::Ruling.new(id: it.id, kind: it.kind, payload: it.payload, created_at_ms: it.created_at_ms) }
      context[:cancelled_ruling_ids] = Results::ActiveRulings.new(engine_rulings).cancelled_ids
      rulings
    end

    def racer(event_id:, bib:)
      require_official!
      RacerDetail.for(Event.find(event_id), bib.to_s.strip)
    end

    def devices(event_id:)
      require_official!("chief")
      Device.where(event_id:).order(:paired_at_ms, :id)
    end

    def disciplines
      require_official!
      Disciplines::TABLE
    end
  end
end
