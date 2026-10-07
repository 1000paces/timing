class RenameRidersToRacers < ActiveRecord::Migration[8.1]
  def change
    rename_table :riders, :racers
    rename_column :registrations, :rider_id, :racer_id
  end
end
