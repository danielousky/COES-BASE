class RemoveStudyPlanToSubjectType < ActiveRecord::Migration[7.0]
  def change
    remove_column :subject_types, :study_plan_id
  end
end
