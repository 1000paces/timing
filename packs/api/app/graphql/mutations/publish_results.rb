module Mutations
  class PublishResults < RulingMutation
    description "Mark the race's current standings official"
    argument :race_id, ID

    def resolve(race_id:)
      require_official!("chief")
      race = Race.find(race_id)
      result = StandingsService.report(race.event).output.races.find { it.race_id == race.id }
      return refuse("Race has not started") if result.nil? || result.state == :not_started
      record(event: race.event, kind: "publish_results", payload: { race_id: race.id, result_digest: result.digest })
    end
  end
end
