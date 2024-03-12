class AddEnabledByLevelToSchool < ActiveRecord::Migration[7.0]
  def change
    add_column :schools, :enable_by_level, :boolean, default: false
  end
end