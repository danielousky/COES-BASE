class RemoveSchoolAndDepartamentToArea < ActiveRecord::Migration[7.0]
  def change
    remove_column :areas, :departament_id
    remove_column :areas, :school_id
  end
end
