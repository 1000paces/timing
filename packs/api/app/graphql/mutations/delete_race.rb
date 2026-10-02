module Mutations
  class DeleteRace < BaseMutation
    argument :id, ID

    def resolve(id:)
      require_official!("admin")
      race = Race.find(id)
      return { errors: ["#{race.name} has registrations and can't be deleted"] } if race.registrations.exists?
      if StandingsService.report(race.event).output.races.find { it.race_id == race.id }&.start_at_ms
        return { errors: ["#{race.name} has started and can't be deleted"] }
      end
      race.destroy!
      { errors: [] }
    end
  end
end
