# == Schema Information
#
# Table name: requirement_by_subject_types
#
#  id               :bigint           not null, primary key
#  required_credits :integer          default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  study_plan_id    :bigint           not null
#  subject_type_id  :bigint           not null
#
# Indexes
#
#  index_requirement_by_subject_types_on_study_plan_id    (study_plan_id)
#  index_requirement_by_subject_types_on_subject_type_id  (subject_type_id)
#
# Foreign Keys
#
#  fk_rails_...  (study_plan_id => study_plans.id)
#  fk_rails_...  (subject_type_id => subject_types.id)
#
class RequirementBySubjectType < ApplicationRecord
    belongs_to :study_plan
    belongs_to :subject_type

    validates :study_plan, presence: true
    validates :subject_type, presence: true
    validates :required_credits, presence: true, numericality: { only_integer: true, in: 0..1000 }

    def name
        "#{subject_type.name} (#{required_credits} CRED)"
    end

    rails_admin do
        visible false

        edit do
            fields :subject_type, :required_credits

        end
    end
end
