class AddLevelsToStudyPlan < ActiveRecord::Migration[7.0]
  def change
    add_column :study_plans, :levels, :integer, default: 10, null: false
  end
end