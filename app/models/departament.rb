# == Schema Information
#
# Table name: departaments
#
#  id         :bigint           not null, primary key
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  school_id  :bigint           not null
#
# Indexes
#
#  index_departaments_on_school_id  (school_id)
#
# Foreign Keys
#
#  fk_rails_...  (school_id => schools.id)
#
class Departament < ApplicationRecord
	# ASSOCIATIONS:
	belongs_to :school
	has_and_belongs_to_many :areas
	# has_many :areas#, dependent: :restrict_with_error
	has_many :subjects, through: :areas
	has_many :courses, through: :subjects
	has_many :sections, through: :courses
	has_many :academic_records, through: :sections
	# VALIDATIONS:
	validates :name, presence: true#, uniqueness: {case_sensitive: false}

	validates_uniqueness_of :name, scope: [:school_id], message: 'Ya se tiene un departamento con ese nombre para la escuela', field_name: false, case_sensitive: false

	validates :school, presence: true

	def desc
		"#{name} (#{school&.code})"
	end

	def full_description
		"#{name} - #{school&.name}"
	end

	rails_admin do
		visible do
			bindings[:controller].current_user&.admin&.authorized_read? 'Subject'
		end

		navigation_label 'Config General'
		navigation_icon 'fa-regular fa-landmark-dome'
		weight 0

		edit do
			field :school do
				inline_edit false
				inline_add false
			end
			field :name do
				html_attributes do
					{:onInput => "$(this).val($(this).val().toUpperCase())"}
				end				
			end
		end

		update do

			field :school do
				inline_edit false
				inline_add false
			end
			field :name do
				html_attributes do
					{:onInput => "$(this).val($(this).val().toUpperCase())"}
				end				
			end			
			# field :areas do
			# 	inline_add false
			# end
		end

		list do
			fields :school, :name, :areas
		end

		show do
			field :full_description do
				label 'Descripción'
			end
			
			field :areas do
				pretty_value do
					bindings[:view].render(template: '/areas/index', locals: {areas: bindings[:object].areas.order(name: :asc)})
				  end				
			end
		end
	end

end
