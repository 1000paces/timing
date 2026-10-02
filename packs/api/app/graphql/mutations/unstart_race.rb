module Mutations
  class UnstartRace < RulingMutation
    description "Undo a race's start (started by mistake); it can then be started again"
    argument :race_id, ID

    def resolve(race_id:)
      require_official!("chief")
      race = Race.find(race_id)
      event = race.event
      event.with_lock do
        report = StandingsService.report(event)
        next refuse("Standings are out of date; try again in a moment") if report.stale
        next refuse("#{race.name} hasn't started") unless report.output.races.find { it.race_id == race.id }&.start_at_ms

        active = Results::ActiveRulings.new(ResultsSnapshot.for(event, now_ms: Clock.now_ms).rulings)
        starts = active.of("set_race_start").select { it.payload["race_id"] == race.id }
        next refuse("#{race.name} was started with its whole start group; it can't be unstarted on its own") if starts.empty?

        starts.map { record(event:, kind: "revert", payload: { ruling_id: it.id }, reason: "unstart") }.last
      end
    end
  end
end
