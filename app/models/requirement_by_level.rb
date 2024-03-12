# == Schema Information
#
# Table name: requirement_by_levels
#
#  id                :bigint           not null, primary key
#  level             :integer
#  required_subjects :integer
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  study_plan_id     :bigint           not null
#  subject_type_id   :bigint           not null
#
# Indexes
#
#  index_requirement_by_levels_on_study_plan_id    (study_plan_id)
#  index_requirement_by_levels_on_subject_type_id  (subject_type_id)
#  study_plan_level_subject_type_unique            (study_plan_id,level,subject_type_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (study_plan_id => study_plans.id)
#  fk_rails_...  (subject_type_id => subject_types.id)
#
class RequirementByLevel < ApplicationRecord
    # ASSOSIATIONS:
    belongs_to :study_plan
    belongs_to :subject_type
  
    # VALIDATIONS:
    validates :study_plan, presence: true
    validates :subject_type, presence: true
    validates :level, presence: true
    validates :required_subjects, presence: true
    validates_uniqueness_of :study_plan_id, scope: [:level, :subject_type_id], message: 'la relación ya existe', field_name: false
  
    rails_admin do
      visible false
    end
  
  end
