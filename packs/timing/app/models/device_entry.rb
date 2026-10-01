class DeviceEntry < ApplicationRecord
  include AppendOnly

  belongs_to :event
  belongs_to :device

  before_validation { self.received_at_ms ||= (Time.now.to_r * 1000).to_i }

  validates :device_seq, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :device_id }
  validates :prev_hash, :entry_hash, :received_at_ms, presence: true
end
