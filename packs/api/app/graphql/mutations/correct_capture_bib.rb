module Mutations
  # Any official may correct or add the bib on their own console crossings: a
  # bib entry is appended to their console's log (the tap itself is never
  # edited). Chiefs and admins may correct any device's crossing: that is an
  # official assign_bib ruling, which wins everywhere and reaches phones on sync.
  class CorrectCaptureBib < BaseMutation
    description "Correct or add a crossing's bib: your own console captures, or any device's for chiefs"
    argument :capture_id, ID
    argument :bib, String

    field :capture, Types::CaptureType

    def resolve(capture_id:, bib:)
      official = require_official!("timer")
      capture = Capture.find(capture_id)
      mine = capture.device == ConsoleDevice.find(event: capture.event, official:)
      chief = official.at_least?("chief")
      return refuse("You can only change your own captures") unless mine || chief
      return refuse("Enter a bib (delete the crossing to take it back)") if bib.strip.empty?
      return refuse("That capture is deleted") if CaptureLaps.voided_ids(capture.event).include?(capture.id)

      assigned = CaptureLaps.assigned_bibs(capture.event)[capture.id]
      if mine && !assigned
        BibAssignment.record!(capture:, bib:)
      elsif chief
        # The console is the master copy: a chief's fix to another device's
        # crossing (or over an official's earlier one) is an official ruling.
        ruling = RulingWriter.write(event: capture.event, official:, kind: "assign_bib", payload: { capture_id: capture.id, bib: bib.strip })
        return refuse(ruling.errors.full_messages.join("; ")) unless ruling.persisted?
      else
        return refuse("An official assigned bib #{assigned} to this crossing; change it in the review queue")
      end
      { capture:, errors: [] }
    end

    private

    def refuse(message) = { capture: nil, errors: [message] }
  end
end
