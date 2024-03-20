class AddShortNameToSchool < ActiveRecord::Migration[7.0]
  def change
    add_column :schools, :short_name, :string
  end
end
