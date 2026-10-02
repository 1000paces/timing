module Mutations
  class CreatePairingToken < BaseMutation
    argument :event_id, ID

    field :token, String
    field :expires_at_ms, Types::Millis
    field :pairing_url, String

    def resolve(event_id:)
      official = require_official!("admin")
      record, raw = PairingToken.issue!(event: Event.find(event_id), official:)
      { token: raw, expires_at_ms: record.expires_at_ms, pairing_url: "#{context[:base_url]}/capture/pair?token=#{raw}", errors: [] }
    end
  end
end
