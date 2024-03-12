class CreateRequirementByLevels < ActiveRecord::Migration[7.0]
  def change
    create_table :requirement_by_levels do |t|
      t.integer :level
      t.references :study_plan, null: false, foreign_key: true
      t.references :subject_type, null: false, foreign_key: true
      t.integer :required_subjects

      t.timestamps
    end
    add_index :requirement_by_levels, [:study_plan_id, :level, :subject_type_id], unique: true, name: 'study_plan_level_subject_type_unique'
  end
end