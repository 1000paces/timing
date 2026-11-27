# A phone moved to another timing point (null checkpoint: the finish). In the
# log so the audit trail shows when; each capture also carries its own.
class DeviceLocation < DeviceEntry
  validates :captured_at_ms, presence: true
end
