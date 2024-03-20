# == Schema Information
#
# Table name: group_tutorials
#
#  id         :bigint           not null, primary key
#  name_group :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class GroupTutorial < ApplicationRecord

    ## Relations
    has_many :tutorials, dependent: :destroy
    accepts_nested_attributes_for :tutorials, allow_destroy: true

    ## HISTORY:
    has_paper_trail on: [:create, :destroy, :update]
    before_create :paper_trail_create
    before_destroy :paper_trail_destroy
    before_update :paper_trail_update

    ## Rich Text
    has_rich_text :description

    ## Validations
    validates :name_group, presence: true
    #validates :tutorials, presence: true

    def name
    	name_group
    end

    rails_admin do
		navigation_label 'Informativos'
		navigation_icon 'fa-regular fa-laptop-code'

		list do
			field :name_group
			field :description
			field :tutorials
		end		

		edit do
			field :name_group
			field :description
		end		

		show do
			field :name_group
			field :description
			field :tutorials
		end		
	end

    
    private

        def paper_trail_update
            changed_fields = self.changes.keys - ['created_at', 'updated_at']
            object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
            self.paper_trail_event = "¡#{object} actualizado en #{changed_fields.to_sentence}"
        end  

        def paper_trail_create
            object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
            self.paper_trail_event = "¡Tutorial creado!"
        end  

        def paper_trail_destroy
            object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
            self.paper_trail_event = "¡Tutorial eliminado!"
        end
end
