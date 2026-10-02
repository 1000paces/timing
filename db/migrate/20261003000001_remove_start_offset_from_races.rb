# Waves are started by hand on the console's Start screen, so races no longer
# carry a planned offset from their start group's gun.
class RemoveStartOffsetFromRaces < ActiveRecord::Migration[8.1]
  def change
    remove_column :races, :start_offset_ms, :integer, null: false, default: 0
  end
end
