# == Schema Information
#
# Table name: authorizables
#
#  id                   :bigint           not null, primary key
#  description          :string
#  icon                 :string
#  klazz                :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  area_authorizable_id :bigint           not null
#
# Indexes
#
#  index_authorizables_on_area_authorizable_id            (area_authorizable_id)
#  index_authorizables_on_klazz_and_area_authorizable_id  (klazz,area_authorizable_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (area_authorizable_id => area_authorizables.id)
#
class Authorizable < ApplicationRecord

  IMPORTABLES = ['Student', 'Teacher', 'Subject', 'Section', 'AcademicRecord']
  UNEXPORTABLES = ['School', 'Faculty', 'StudyPlan']
  UNDELETABLES = ['School', 'StudyPlan', 'Faculty', 'EnrollAcademicProcess']
  UNCREABLES = ['School', 'Faculty']
  # ASSOCIATIONS:
  belongs_to :area_authorizable

  # VALIDATIONS:
  validates :klazz, presence: true, uniqueness: true

  # FUNCTIONS:
  def name
    ApplicationController.helpers.translate_model klazz.tableize.singularize if klazz
  end
  # RAILS_ADMIN:
  rails_admin do
    # visible false
    navigation_label 'DESARROLLO'
    navigation_icon 'fa-solid fa-door-open'


    edit do
      field :klazz #do
      #   formatted_value do
      #     objetos = ApplicationRecord.descendants

      #     bindings[:view].collection_select(:authorizable, :name, objetos, :name, :name, {class: "text-field form-control", required: true}) << value
          
      #   end
      # end
      fields :description, :icon
    end
  end
end
