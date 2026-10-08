module Mutations
  class StartRaces < BaseMutation
    description "Start the selected races together, at hub time"
    argument :race_ids, [ ID ]

    field :rulings, [ Types::RulingType ], null: false

    def resolve(race_ids:)
      official = require_official!("chief")
      ids = race_ids.uniq
      return refuse("Select at least one race") if ids.empty?
      races = Race.where(id: ids).to_a
      raise GraphQL::ExecutionError, "Not found" if races.size != ids.size
      return refuse("Races must belong to one event") if races.map(&:event_id).uniq.size > 1

      event = races.first.event
      result = nil
      # Lock so a double click or two officials can't start the same race twice.
      event.with_lock do
        report = StandingsService.report(event)
        next result = refuse("Standings are out of date; try again in a moment") if report.stale
        started = report.output.races.select(&:start_at_ms).map(&:race_id)
        already = races.select { started.include?(it.id) }
        next result = refuse(*already.map { "#{it.name} has already started" }) if already.any?

        at_ms = Clock.now_ms
        rulings = races.map { |race| RulingWriter.write(event:, official:, kind: "set_race_start", payload: { race_id: race.id, at_ms: }) }
        if (failed = rulings.find { !it.persisted? })
          result = refuse(*failed.errors.full_messages)
          raise ActiveRecord::Rollback
        end
        result = { rulings:, errors: [] }
      end
      result
    end

    private

    def refuse(*messages) = { rulings: [], errors: messages }
  end
end
