module Mutations
  class CreatePairingToken < BaseMutation
    argument :event_id, ID
    argument :checkpoint_id, ID, required: false

    field :token, String
    field :expires_at_ms, Types::Millis
    field :pairing_url, String

    def resolve(event_id:, checkpoint_id: nil)
      official = require_official!("chief")
      event = Event.find(event_id)
      if checkpoint_id && !event.checkpoints.exists?(id: checkpoint_id)
        return { token: nil, expires_at_ms: nil, pairing_url: nil, errors: [ "That checkpoint isn't on this event's course" ] }
      end
      record, raw = PairingToken.issue!(event:, official:, checkpoint_id:)
      { token: raw, expires_at_ms: record.expires_at_ms, pairing_url: "#{context[:base_url]}/capture-app/?pair=#{PairingToken.normalize(raw)}", errors: [] }
    end
  end
end
