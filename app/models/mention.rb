# == Schema Information
#
# Table name: mentions
#
#  id                      :bigint           not null, primary key
#  name                    :string
#  total_required_subjects :integer          not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  study_plan_id           :bigint           not null
#
# Indexes
#
#  index_mentions_on_study_plan_id  (study_plan_id)
#
# Foreign Keys
#
#  fk_rails_...  (study_plan_id => study_plans.id)
#
class Mention < ApplicationRecord
  belongs_to :study_plan
  has_and_belongs_to_many :subjects

  rails_admin do
    visible false
    edit do
      fields :name, :total_required_subjects
      field :subjects do
        inline_add false
        inline_edit false
      end
    end
  end
end
