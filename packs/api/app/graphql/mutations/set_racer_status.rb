module Mutations
  # Marks a racer DNF or DNS with a ruling, or clears it by reverting the
  # racer's active DNF/DNS/DSQ rulings. Every change stays in the ruling history.
  class SetRacerStatus < BaseMutation
    STATUS_KINDS = %w[dnf dns dsq].freeze

    argument :event_id, ID
    argument :bib, String
    argument :status, Types::RacerStatusChangeEnum
    argument :reason, String, required: false

    def resolve(event_id:, bib:, status:, reason: nil)
      official = require_official!("chief")
      event = Event.find(event_id)
      return { errors: ["Bib #{bib} is not registered in this event"] } unless event.registrations.exists?(bib:)

      writes = status ? [[status, { bib: }]] : active_status_rulings(event, bib).map { ["revert", { ruling_id: it.id }] }
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

    private

    def active_status_rulings(event, bib)
      engine = Ruling.where(event:).map { Results::Ruling.new(id: it.id, kind: it.kind, payload: it.payload, created_at_ms: it.created_at_ms) }
      Results::ActiveRulings.new(engine).all.select { STATUS_KINDS.include?(it.kind) && it.payload["bib"].to_s == bib }
    end
  end
end
