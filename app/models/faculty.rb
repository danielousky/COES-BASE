# == Schema Information
#
# Table name: faculties
#
#  id             :bigint           not null, primary key
#  code           :string
#  coes_boss_name :string
#  contact_email  :string
#  name           :string
#  short_name     :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class Faculty < ApplicationRecord

	validates :code, presence: true, uniqueness: {case_sensitive: false}
	validates :name, presence: true, uniqueness: {case_sensitive: false}

	before_save :clean_name_and_code

	# HOOKS:
	def clean_name_and_code
	self.name.delete! '^A-Za-z|áÁÄäËëÉéÍÏïíÓóÖöÚúÜüñÑ '
	self.name.strip!
	self.name.upcase!

	self.code.delete! '^A-Za-z|áÁÄäËëÉéÍÏïíÓóÖöÚúÜüñÑ'
	self.code.strip!
	self.code.upcase!
	end

	# HISTORY:
	has_paper_trail on: [:create, :destroy, :update]

	before_create :paper_trail_create
	before_destroy :paper_trail_destroy
	before_update :paper_trail_update

	# ASSOCIATIONS:
	# has_many:
	has_many :admins, as: :env_authorizable, dependent: :destroy
	has_many :schools, dependent: :destroy
	has_many :academic_processes, through: :schools
	has_many :periods, through: :academic_processes

	has_many :entity_bank_accounts, as: :bank_accountable, dependent: :destroy
	has_many :bank_accounts, through: :entity_bank_accounts, dependent: :destroy

	# accepts_nested_attributes_for :bank_accounts, allow_destroy: true

	# has_many :grades, through: :schools
	# has_many :students, through: :grades
	has_one_attached :logo
	has_one_attached :coes_signature
	has_one_attached :coes_stamp	
	# VALIDATIONS:
	validates :code, presence: true, uniqueness: {case_sensitive: false}
	validates :name, presence: true, uniqueness: {case_sensitive: false}
	validates :contact_email, presence: true
	validates :coes_boss_name, presence: true

	rails_admin do
		navigation_label 'Config General'
		navigation_icon 'fa-regular fa-building-columns'
		visible false

		list do
			exclude_fields :created_at, :updated_at
		end

		show do
			fields :code, :name, :logo
		end


		edit do
			field :code do
				html_attributes do
					{:length => 3, :size => 3, :onInput => "$(this).val($(this).val().toUpperCase().replace(/[^A-Za-z]/g,''))"}
				end
			end

			field :short_name do
				html_attributes do
					{:onInput => "$(this).val($(this).val().toUpperCase())"}
				end				
			end

			field :name do
				html_attributes do
					{:onInput => "$(this).val($(this).val().toUpperCase())"}
				end				
			end
			fields :contact_email, :coes_boss_name, :logo, :coes_signature, :coes_stamp
			field :bank_accounts do
				inline_edit false
				inline_add false
			end
		end
	end

	private


    def paper_trail_update
      # changed_fields = self.changes.keys - ['created_at', 'updated_at']
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      # self.paper_trail_event = "¡#{object} actualizado en #{changed_fields.to_sentence}"
      self.paper_trail_event = "¡#{object} actualizada!"
    end  

    def paper_trail_create
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      self.paper_trail_event = "¡#{object} registrada!"
    end  

    def paper_trail_destroy
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      self.paper_trail_event = "¡Facultad eliminada!"
    end

end
