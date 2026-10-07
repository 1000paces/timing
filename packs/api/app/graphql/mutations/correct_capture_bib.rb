module Mutations
  # Any official may correct or add the bib on their own console crossings. The
  # tap itself is never edited: a bib entry is appended to the device's log, as
  # a tablet does for "tap now, bib later". An official's assign_bib ruling wins.
  class CorrectCaptureBib < BaseMutation
    description "Correct or add the bib on one of the signed-in official's own console captures"
    argument :capture_id, ID
    argument :bib, String

    field :capture, Types::CaptureType

    def resolve(capture_id:, bib:)
      official = require_official!("timer")
      capture = Capture.find(capture_id)
      return refuse("You can only change your own captures") unless capture.device == ConsoleDevice.find(event: capture.event, official:)
      return refuse("Enter a bib (delete the crossing to take it back)") if bib.strip.empty?
      return refuse("That capture is deleted") if CaptureLaps.voided_ids(capture.event).include?(capture.id)
      if (assigned = CaptureLaps.assigned_bibs(capture.event)[capture.id])
        return refuse("An official assigned bib #{assigned} to this crossing; change it in the review queue")
      end

      BibAssignment.record!(capture:, bib:)
      { capture:, errors: [] }
    end

    private

    def refuse(message) = { capture: nil, errors: [message] }
  end
end
