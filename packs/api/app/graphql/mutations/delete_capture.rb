module Mutations
  # Any official may delete their own console captures (a mistaken tap). The
  # capture stays in the log; a void_capture ruling by that official hides it
  # from results, and it can be reverted like any ruling.
  class DeleteCapture < BaseMutation
    description "Void one of the signed-in official's own console captures"
    argument :capture_id, ID

    def resolve(capture_id:)
      official = require_official!("timer")
      capture = Capture.find(capture_id)
      return { errors: ["You can only delete your own captures"] } unless capture.device == ConsoleDevice.find(event: capture.event, official:)
      return { errors: ["That capture is already deleted"] } if CaptureLaps.voided_ids(capture.event).include?(capture.id)

      ruling = RulingWriter.write(event: capture.event, official:, kind: "void_capture", payload: { capture_id: capture.id })
      { errors: ruling.errors.full_messages }
    end
  end
end
