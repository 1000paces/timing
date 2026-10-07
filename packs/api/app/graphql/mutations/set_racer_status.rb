module Mutations
  # Marks a racer DNF, DNS or DSQ with a ruling, or clears it by reverting the
  # racer's active DNF/DNS/DSQ rulings. Every change stays in the ruling history.
  class SetRacerStatus < BaseMutation
    argument :event_id, ID
    argument :bib, String
    argument :status, Types::RacerStatusChangeEnum
    argument :reason, String, required: false

    def resolve(event_id:, bib:, status:, reason: nil)
      official = require_official!("chief")
      event = Event.find(event_id)
      return { errors: ["Bib #{bib} is not registered in this event"] } unless event.registrations.exists?(bib:)

      clearing = RacerStatuses.active_rulings(event).select { it.payload["bib"].to_s == bib }
      writes = status ? [[status, { bib: }]] : clearing.map { ["revert", { ruling_id: it.id }] }
      written = []
      Ruling.transaction do
        writes.each do |kind, payload|
          written << RulingWriter.write(event:, official:, kind:, payload:, reason:)
          raise ActiveRecord::Rollback if written.last.new_record?
        end
      end
      failed = written.find(&:new_record?)
      { errors: failed ? failed.errors.full_messages : [] }
    end
  end
end
