module Mutations
  # Shared checks for the racer-panel fixes (chief and above, via RulingMutation#record).
  module OfficiatingFix
    private

    def registered!(event, bib)
      return nil if event.registrations.exists?(bib: bib.to_s.strip)
      refuse("Bib #{bib} is not registered in this event")
    end

    # The engine's view of a racer (crossings, start) for checks.
    def racer_row(event, bib)
      registration = event.registrations.find_by(bib:)
      result = StandingsService.report(event).output.races.find { it.race_id == registration&.race_id }
      [ result, result&.rows&.find { it.bib == bib } ]
    end
  end
end
