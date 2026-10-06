class AddAgeNextYearToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :age_next_year, :boolean, null: false, default: false
    reversible { |dir| dir.up { execute "UPDATE events SET age_next_year = #{connection.quoted_true} WHERE discipline = 'cyclocross'" } }
  end
end
