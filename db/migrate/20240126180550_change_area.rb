class ChangeArea < ActiveRecord::Migration[7.0]
  def change
    add_reference :areas, :departament
    remove_reference :areas, :parent_area
  end
end
