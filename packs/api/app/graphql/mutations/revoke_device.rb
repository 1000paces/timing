module Mutations
  class RevokeDevice < BaseMutation
    argument :device_id, ID

    field :device, Types::DeviceType

    def resolve(device_id:)
      require_official!("chief")
      device = Device.find(device_id)
      device.revoke!
      { device:, errors: [] }
    end
  end
end
