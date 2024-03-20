# == Schema Information
#
# Table name: areas
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Area < ApplicationRecord  
  # HISTORY:
  has_paper_trail on: [:create, :destroy, :update]

  before_create :paper_trail_create
  before_destroy :paper_trail_destroy
  before_update :paper_trail_update

  # ASSOCITATIONS:
  has_and_belongs_to_many :departaments
  has_many :schools, through: :departaments
  has_many :admins, as: :env_authorizable 

  has_many :subjects, dependent: :restrict_with_error
  has_many :sections, through: :subjects
  has_many :academic_records, through: :sections
  # accepts_nested_attributes_for :subjects

  # VALIDATIONS:
  validates :name, presence: true, uniqueness: {case_sensitive: false}
  validates_with SameSchoolToAreaValidator, field_name: false

  # SCOPES:
  # scope :main, -> {where(departament_id: nil)}
  # scope :catedras, -> {where.not(departament_id: nil)}
  scope :names, -> {select(:name).map{|ar| ar.name}}

  # CALLBACKS:
  before_save :clean_name

  # HOOKS:
  def clean_name
    self.name.strip!
    self.name.upcase!
  end

  # FUNCTIONS:

  def description
    "#{self.id}: #{self.name}"
  end

  def total_subjects
    subjects.count
  end

  rails_admin do
    visible do
      bindings[:controller].current_user&.admin?
    end
    navigation_label 'Config General'
    navigation_icon 'fa-regular fa-book-open'
    weight 1

    list do
      field :name
      field :departaments
      field :total_subjects do
        label 'Total Asignaturas'
      end
    end
    show do
      field :name
      field :departaments
      field :subjects do
        pretty_value do
          bindings[:view].render(template: '/subjects/index', locals: {subjects: bindings[:object].subjects.order(code: :asc)})
        end
      end
    end 

    edit do
      field :name do
        html_attributes do
          {:onInput => "$(this).val($(this).val().toUpperCase())"}
        end         
      end

      field :departaments do
        inline_edit false
      end

    end 

    modal do
      field :name
      exclude_fields :departaments
    end


    export do
      fields :name, :departaments
    end

  end

  private


    def paper_trail_update
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      self.paper_trail_event = "¡#{object} actualizada!"
    end  

    def paper_trail_create
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      self.paper_trail_event = "¡#{object} registrada!"
    end  

    def paper_trail_destroy
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      self.paper_trail_event = "¡Asignatura eliminada!"
    end  

end
