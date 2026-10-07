module Mutations
  # Any official may delete their own console captures (a mistaken tap); chiefs
  # and admins may delete any device's. The capture stays in the log; a
  # void_capture ruling by that official hides it everywhere and can be reverted.
  class DeleteCapture < BaseMutation
    description "Void a crossing: your own console captures, or any device's for chiefs"
    argument :capture_id, ID

    def resolve(capture_id:)
      official = require_official!("timer")
      capture = Capture.find(capture_id)
      mine = capture.device == ConsoleDevice.find(event: capture.event, official:)
      return { errors: ["You can only delete your own captures"] } unless mine || official.at_least?("chief")
      return { errors: ["That capture is already deleted"] } if CaptureLaps.voided_ids(capture.event).include?(capture.id)

      ruling = RulingWriter.write(event: capture.event, official:, kind: "void_capture", payload: { capture_id: capture.id })
      { errors: ruling.errors.full_messages }
    end
  end
end
