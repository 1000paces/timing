module Mutations
  class SetLapCount < BaseMutation
    description "Set the lap count for a race and every race that finishes with it (its cohort)"
    argument :race_id, ID
    argument :laps, Integer

    field :rulings, [ Types::RulingType ], null: false

    def resolve(race_id:, laps:)
      official = require_official!("chief")
      race = Race.find(race_id)
      rulings = nil
      Ruling.transaction do
        rulings = race.cohort.map { RulingWriter.write(event: race.event, official:, kind: "set_lap_count", payload: { race_id: it.id, laps: }) }
        if (failed = rulings.find { !it.persisted? })
          rulings = failed.errors.full_messages
          raise ActiveRecord::Rollback
        end
      end
      rulings.first.is_a?(String) ? { rulings: [], errors: rulings } : { rulings:, errors: [] }
    end
  end
end
