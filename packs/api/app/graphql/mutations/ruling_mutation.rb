module Mutations
  class RulingMutation < BaseMutation
    field :ruling, Types::RulingType

    private

    def record(event:, kind:, payload:, reason: nil, role: "chief")
      official = require_official!(role)
      ruling = RulingWriter.write(event:, official:, kind:, payload:, reason:)
      ruling.persisted? ? { ruling:, errors: [] } : { ruling: nil, errors: ruling.errors.full_messages }
    end

    def refuse(message) = { ruling: nil, errors: [ message ] }
  end
end
