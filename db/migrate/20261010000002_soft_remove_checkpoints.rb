# A removed checkpoint stays (a phone offline at it may still push entries
# naming it) but leaves the course: no position, removed_at_ms set.
class SoftRemoveCheckpoints < ActiveRecord::Migration[8.1]
  def change
    add_column :checkpoints, :removed_at_ms, :bigint
    change_column_null :checkpoints, :position, true
  end
end
