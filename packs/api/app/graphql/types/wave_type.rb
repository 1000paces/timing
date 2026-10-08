module Types
  # object: { scheduled_at_ms:, start_at_ms:, races: [Race] }
  class WaveType < BaseObject
    description "Races that finish together (a scheduled start)"
    field :scheduled_at_ms, Millis
    field :start_at_ms, Millis, null: false, description: "When its first race started"
    field :races, [ RaceType ], null: false
    field :as_of_ms, Millis, null: false, description: "Hub time when this was looked up (a flag from the line is stamped with it)"

    def scheduled_at_ms = object[:scheduled_at_ms]
    def start_at_ms = object[:start_at_ms]
    def races = object[:races]
    def as_of_ms = object[:as_of_ms]
  end
end
