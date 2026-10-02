module Types
  class StandingsReportType < BaseObject
    field :races, [RaceStandingsType], null: false
    field :suggestions, [SuggestionType], null: false
    field :unassigned, [UnassignedCaptureType], null: false
    field :computed_at_ms, Millis
    field :stale, Boolean, null: false
    field :error, String

    def races
      by_id = object.event.races.includes(:category).index_by(&:id)
      object.output.races.filter_map { |result| (race = by_id[result.race_id]) && { result:, race: } }
    end

    def suggestions = object.output.suggestions
    def unassigned = object.output.unassigned
  end
end
