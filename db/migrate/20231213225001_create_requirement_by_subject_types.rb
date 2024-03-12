class CreateRequirementBySubjectTypes < ActiveRecord::Migration[7.0]
  def change
    create_table :requirement_by_subject_types do |t|
      t.references :study_plan, null: false, index: true, foreign_key: true
      t.references :subject_type, null: false, index: true, foreign_key: true
      t.integer :required_credits, default: 0, null: false
      t.timestamps
    end
  end
end
