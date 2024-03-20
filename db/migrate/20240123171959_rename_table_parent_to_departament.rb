class RenameTableParentToDepartament < ActiveRecord::Migration[7.0]
  def change
    rename_table "parent_areas", "departaments"
  end
end
