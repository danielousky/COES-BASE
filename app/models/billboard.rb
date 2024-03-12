# == Schema Information
#
# Table name: billboards
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(FALSE)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Billboard < ApplicationRecord
	# HISTORY:
	has_paper_trail on: [:create, :destroy, :update]

	before_create :paper_trail_create
	before_destroy :paper_trail_destroy
	before_update :paper_trail_update

	# Rich Text
    has_rich_text :content

    scope :activas, -> {where(active: true)}

    validates :content, presence: true

	def activada_valor
		activa ? 'Activada' : 'Desactivada'
	end

	rails_admin do
		navigation_label 'Informativos'
		navigation_icon 'fa-regular fa-panorama'

		edit do
			field :active
			field :content do
				help 'Si desea agregar imágenes tome en cuenta el tamaño de la misma y su ajuste a la pantalla dónde se desplegará'
			end
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
			self.paper_trail_event = "¡Cartelera creada!"
		end  

		def paper_trail_destroy
			object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
			self.paper_trail_event = "¡Cartelera eliminada!"
		end
		
end
