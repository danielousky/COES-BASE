class RemoveReferenceStudyPlanToSubjectType < ActiveRecord::Migration[7.0]
  def change
    remove_foreign_key :subject_types, :study_plans
  end
end
