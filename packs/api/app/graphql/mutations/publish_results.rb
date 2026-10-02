module Mutations
  class PublishResults < RulingMutation
    description "Mark the race's current standings official"
    argument :race_id, ID

    def resolve(race_id:)
      require_official!("chief")
      race = Race.find(race_id)
      # Lock so the digest we record is of the standings as of this write, not a concurrent change.
      race.event.with_lock do
        report = StandingsService.report(race.event)
        next refuse("Standings are out of date; try again in a moment") if report.stale
        result = report.output.races.find { it.race_id == race.id }
        next refuse("Race has not started") if result.nil? || result.state == :not_started
        record(event: race.event, kind: "publish_results", payload: { race_id: race.id, result_digest: result.digest })
      end
    end
  end
end
