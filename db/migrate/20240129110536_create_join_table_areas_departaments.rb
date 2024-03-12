class CreateJoinTableAreasDepartaments < ActiveRecord::Migration[7.0]
  def change
    create_join_table :areas, :departaments do |t|
      t.index [:area_id, :departament_id]
      t.index [:departament_id, :area_id]
    end
  end
end
