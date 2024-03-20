class AddShortNameToFaculty < ActiveRecord::Migration[7.0]
  def change
    add_column :faculties, :short_name, :string
  end
end
