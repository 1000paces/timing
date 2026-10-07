# A device takes back one of its own taps (the phone's delete). Counts like an
# official's void_capture ruling in results and on the Capture screens.
class CaptureVoid < DeviceEntry
  belongs_to :capture

  validate :same_device_as_capture

  def self.record!(capture:) = append!(device: capture.device, capture:)

  private

  def same_device_as_capture
    errors.add(:capture, "must belong to the same device") if capture && capture.device_id != device_id
  end
end
