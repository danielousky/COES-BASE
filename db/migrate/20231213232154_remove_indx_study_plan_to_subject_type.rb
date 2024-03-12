class RemoveIndxStudyPlanToSubjectType < ActiveRecord::Migration[7.0]
  def change
    remove_index :subject_types, :study_plan_id
  end
end
