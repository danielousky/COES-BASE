# == Schema Information
#
# Table name: area_authorizables
#
#  id          :bigint           not null, primary key
#  description :string
#  icon        :string
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class AreaAuthorizable < ApplicationRecord

	# HISTORY:
	has_paper_trail on: [:create, :destroy, :update]

	before_create :paper_trail_create
	before_destroy :paper_trail_destroy
	before_update :paper_trail_update

	# ASSOCIATIONS:
	has_many :authorizables, dependent: :destroy
	accepts_nested_attributes_for :authorizables, allow_destroy: true#, reject_if: proc { |attributes| attributes['area_authorizable_id'].blank? }

	#VALIDATIONS:
	validates :name, presence: true, uniqueness: true

	# FUNTIONS:

	def can_all? admin_id
		can = true
		authorizables.each do |athble|
			athd = Authorized.where(admin_id: admin_id, authorizable_id: athble.id).first
			can = false if !(athd and athd.can_all?)
		end
		return can
	end

	# RAILS_ADMIN:
	rails_admin do
		# visible false
		navigation_label 'DESARROLLO'
		navigation_icon 'fa-solid fa-object-group'
		
		edit do
			fields :name, :description, :icon, :authorizables

		end
		list do
		end
	end

	private

		def paper_trail_update
			changed_fields = self.changes.keys - ['created_at', 'updated_at']
			object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
			self.paper_trail_event = "¡#{object} actualizada en #{changed_fields.to_sentence}"
		end  

		def paper_trail_create
			object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
			self.paper_trail_event = "¡#{object} creada!"
		end  

		def paper_trail_destroy
			object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
			self.paper_trail_event = "¡Área Autorizable eliminada!"
		end
end
