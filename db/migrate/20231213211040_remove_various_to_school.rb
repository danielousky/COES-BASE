class RemoveVariousToSchool < ActiveRecord::Migration[7.0]
  def change
    remove_column :schools, :contact_email
    remove_column :schools, :boss_name    
  end
end
