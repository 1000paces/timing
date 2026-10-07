class DeviceSync < ActiveRecord::Migration[8.1]
  def change
    change_table :devices, bulk: true do |t|
      t.bigint :last_seen_at_ms
      t.bigint :last_sync_at_ms
      t.bigint :clock_offset_ms
      t.bigint :sync_stopped_at_ms
    end
  end
end
