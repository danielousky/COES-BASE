class UpdateFaculty < ActiveRecord::Migration[7.0]
  def change
    add_column :faculties, :coes_boss_name, :string
    add_column :faculties, :contact_email, :string
  end
end
