class AddUniqueLicenseToRiders < ActiveRecord::Migration[8.1]
  def change
    add_index :riders, :license_number, unique: true
  end
end
