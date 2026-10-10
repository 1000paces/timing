module Mutations
  class SetDeviceCheckpoint < BaseMutation
    description "Move a phone to a checkpoint (null: the finish); it picks this up at its next sync"
    argument :device_id, ID
    argument :checkpoint_id, ID, required: false

    field :device, Types::DeviceType

    def resolve(device_id:, checkpoint_id: nil)
      require_official!("chief")
      device = Device.find(device_id)
      if checkpoint_id && !Checkpoint.exists?(id: checkpoint_id, event_id: device.event_id)
        return { device: nil, errors: [ "That checkpoint isn't on this event's course" ] }
      end
      return { device: nil, errors: [ "The phone was moved more recently; try again" ] } unless device.move_to!(checkpoint_id, at_ms: Clock.now_ms)
      { device: device.reload, errors: [] }
    end
  end
end
