module Types
  class QueryType < BaseObject
    field :me, OfficialType, description: "The signed-in official, or null"
    field :events, [ EventType ], null: false
    field :event, EventType, null: false do
      argument :id, ID
    end
    field :disciplines, [ DisciplineType ], null: false, description: "Disciplines, sub-disciplines and finish-with-leader defaults"
    field :officials, [ OfficialType ], null: false
    field :standings, StandingsReportType, null: false do
      argument :event_id, ID
    end

    field :rulings, [ RulingType ], null: false, description: "History: newest first; search by bib or racer name" do
      argument :event_id, ID
      argument :search, String, required: false
      argument :limit, Integer, required: false, default_value: 50
      argument :offset, Integer, required: false, default_value: 0
    end

    field :current_wave, WaveType, description: "The wave on course whose finish flag isn't out yet (latest started), or null" do
      argument :event_id, ID
    end
    field :racer, RacerDetailType, description: "One racer's race: crossings, lap positions, fixes" do
      argument :event_id, ID
      argument :bib, String
    end
    field :devices, [ DeviceType ], null: false do
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

    def rulings(event_id:, search: nil, limit: 50, offset: 0)
      require_official!
      event = Event.find(event_id)
      history = context[:ruling_history] = RulingHistory.new(event)
      rulings = history.rulings
      if (needle = search.to_s.strip.downcase).present?
        names = event.registrations.includes(:racer).to_h { [ it.bib, it.racer.full_name.downcase ] }
        rulings = rulings.select do |r|
          history.describer.bibs_for(r).any? { it.downcase == needle || names[it]&.include?(needle) }
        end
      end
      rulings.drop(offset.clamp(0, nil)).first(limit.clamp(1, 500))
    end

    def current_wave(event_id:)
      require_official!
      CurrentWave.for(Event.find(event_id))
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
