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
    field :races, [RaceType], null: false, description: "In scheduled order, then name"
    field :registrations, [RegistrationType], null: false
    field :my_captures, [CaptureType], null: false, description: "The signed-in official's console captures, newest first" do
      argument :limit, Integer, required: false, default_value: 20
    end

    def races = object.races.to_a.sort_by { [it.scheduled_at_ms, it.name] }
    def my_captures(limit:)
      device = ConsoleDevice.find(event: object, official: context[:current_official])
      return [] unless device
      Capture.where(device:).where.not(id: CaptureLaps.voided_ids(object).to_a).order(device_seq: :desc).limit(limit.clamp(1, 200))
    end

    def registrations = object.registrations.includes(:event, :rider, :race).order(:bib)
  end
end
