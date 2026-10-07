module Types
  class EventType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :date, GraphQL::Types::ISO8601Date, null: false
    field :location, String
    field :discipline, String, null: false
    field :sub_discipline, String
    field :finish_with_leader, Boolean, null: false, description: "Default for races that don't override it"
    field :timezone, String, null: false
    field :age_rule, String, null: false
    field :age_next_year, Boolean, null: false, description: "Racing age as of the end of the following year (season crosses the year boundary, e.g. CX)"
    field :races, [RaceType], null: false, description: "In scheduled order, then name"
    field :registrations, [RegistrationType], null: false, description: "By bib, then racers without one by name"
    field :registration_counts, RegistrationCountsType, null: false
    field :bib_from, Integer, description: "Event-wide bib range, for races without their own"
    field :bib_to, Integer
    field :captures, [CaptureType], null: false, description: "Every device's crossings, newest first by hub time (deleted ones left out)" do
      argument :limit, Integer, required: false, default_value: 100
    end
    field :my_captures, [CaptureType], null: false, description: "The signed-in official's console captures, newest first" do
      argument :limit, Integer, required: false, default_value: 20
    end

    def races = object.races.to_a.sort_by { [it.scheduled_at_ms, it.name] }
    def captures(limit:)
      voided = CaptureLaps.voided_ids(object).to_a
      Capture.where(event: object).where.not(id: voided).includes(:device)
             .order(Arel.sql("captured_at_ms + COALESCE(clock_offset_ms, 0) DESC"), id: :desc).limit(limit.clamp(1, 500))
    end

    def my_captures(limit:)
      device = ConsoleDevice.find(event: object, official: context[:current_official])
      return [] unless device
      Capture.where(device:).where.not(id: CaptureLaps.voided_ids(object).to_a).order(device_seq: :desc).limit(limit.clamp(1, 200))
    end

    def registrations
      object.registrations.includes(:event, :racer, :race).sort_by { [it.bib ? 0 : 1, it.bib.to_i, it.bib.to_s, it.racer.last_name, it.racer.first_name] }
    end

    def registration_counts
      regs = object.registrations
      { registered: regs.count, checked_in: regs.where.not(checked_in_at_ms: nil).count, needs_bib: regs.where(bib: nil).count }
    end
  end
end
