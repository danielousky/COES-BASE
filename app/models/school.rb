# == Schema Information
#
# Table name: schools
#
#  id                           :bigint           not null, primary key
#  code                         :string           not null
#  enable_by_level              :boolean          default(FALSE)
#  enable_change_course         :boolean
#  enable_dependents            :boolean          default(FALSE), not null
#  enable_enroll_payment_report :boolean          default(FALSE), not null
#  enable_subject_retreat       :boolean
#  name                         :string           not null
#  short_name                   :string
#  type_entity                  :integer          default("pregrado"), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  active_process_id            :bigint
#  enroll_process_id            :bigint
#  faculty_id                   :bigint
#
# Indexes
#
#  index_schools_on_active_process_id  (active_process_id)
#  index_schools_on_enroll_process_id  (enroll_process_id)
#  index_schools_on_faculty_id         (faculty_id)
#
# Foreign Keys
#
#  fk_rails_...  (active_process_id => academic_processes.id)
#  fk_rails_...  (enroll_process_id => academic_processes.id)
#
class School < ApplicationRecord

  # HISTORY:
  has_paper_trail on: [:create, :destroy, :update]

  before_create :paper_trail_create
  before_destroy :paper_trail_destroy
  before_update :paper_trail_update
  
  # ASSOCIATIONS
  belongs_to :active_process, foreign_key: 'active_process_id', class_name: 'AcademicProcess', optional: true
  belongs_to :enroll_process, foreign_key: 'enroll_process_id', class_name: 'AcademicProcess', optional: true

  belongs_to :faculty

  has_many :admission_types
  accepts_nested_attributes_for :admission_types

  has_many :academic_processes
  has_many :departaments, dependent: :destroy
  accepts_nested_attributes_for :departaments, allow_destroy: true
  has_many :areas, through: :departaments
  has_many :study_plans, dependent: :destroy
  accepts_nested_attributes_for :study_plans, allow_destroy: true
  has_many :grades, through: :study_plans

  has_many :subjects, through: :areas
  has_many :subject_types, through: :subjects
  has_many :periods, through: :academic_processes
  has_many :admins, as: :env_authorizable 

	has_many :entity_bank_accounts, as: :bank_accountable, dependent: :destroy
	has_many :bank_accounts, through: :entity_bank_accounts, dependent: :destroy

  # accepts_nested_attributes_for :areas, :academic_processes, :admission_types

  # ENUMERATIONS:
  enum type_entity: [:pregrado, :postgrado, :extension, :investigacion]

  # VALIDATIONS
  validates :type_entity, presence: true
  validates :code, presence: true, uniqueness: {case_sensitive: false}
  validates :name, presence: true, uniqueness: {case_sensitive: false}

  # CALLBAKCS:
  after_initialize :set_unique_faculty
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

  def set_unique_faculty
    self.faculty_id = Faculty.first.id if Faculty.count.eql? 1
  end

  # FUNCTIONS:
  def all_grades_to_csv

    CSV.generate do |csv|
      csv << ['Cédula', 'Apellido y Nombre', 'Sede', 'Eficiencia', 'Promedio', 'Ponderado', 'Última Calificación']
      grades.all.each do |grade|
        user = grade.user
        csv << [user.ci, user.reverse_name, grade.student.sede, grade.efficiency, grade.simple_average, grade.weighted_average, grade.academic_records.last&.get_value_by_status]
      end
    end
  end


  def enroll_period_name
    self.enroll_process ? self.enroll_process.name : 'Inscripción Cerrada'
  end

  # def short_name
  #   self.name.split(" ")[2] if self.name
  # end


  def modalities
    academic_processes.map{|ap| ap.modality}.uniq.to_sentence if academic_processes.any?
  end

  def description
    "#{self.code}: #{self.name}. (#{self.faculty.name}) #{self.type_entity.titleize}"
  end

  def enable_dependents?
    (enable_dependents.eql? true)
  end


  rails_admin do
    navigation_label 'Config General'
    navigation_icon 'fa-regular fa-school'
    weight -3
    # visible false


    list do
      checkboxes false
      # field :code do
      #   sortable false
      #   queryable false
      #   filterable false
      #   searchable false
      # end

      field :short_name do
        label 'Escuela'
      end

      field :study_plans

      # field :enable_dependents do
      #   label '¿Prelaciones?'
      #   queryable false
      #   filterable false
      #   searchable false
      #   sortable false
      #   sortable false
      #   pretty_value do

      #     current_user = bindings[:view]._current_user
      #     admin = current_user.admin
      #     active = admin and admin.authorized_manage? 'School'

      #     if active
      #       bindings[:view].render(partial: "/schools/form_dependents", locals: {school: bindings[:object]})
      #     else
      #       value
      #     end
      #   end

      # end

      field :enable_by_level do
        label '¿Inscripciones por Nivel?'
        queryable false
        filterable false
        searchable false
        sortable false
        sortable false
        pretty_value do

          active = bindings[:view]._current_user&.admin&.authorized_manage? 'School'

          if active
            bindings[:view].render(partial: "/schools/form_dependents", locals: {school: bindings[:object]})
          else
            value
          end
        end        
      end

      field :enable_enroll_payment_report do
        label '¿Permitir Reportes de Pago?'
        queryable false
        filterable false
        searchable false
        sortable false
        sortable false
        pretty_value do

          current_user = bindings[:view]._current_user
          admin = current_user.admin
          active = admin&.authorized_manage? 'School'

          if active
            bindings[:view].render(partial: "/schools/form_enroll_payment_reports", locals: {school: bindings[:object]})
          else
            value
          end
        end
      end

      fields :enroll_process do
        label 'Período Inscripción'
        queryable false
        filterable false
        searchable false
        sortable false
        help ''

        # pretty_value do

        #   if bindings[:object].enroll_process
        #     bindings[:view].content_tag(:b, "#{bindings[:object].enroll_process.period.name}", {class: 'bg-success badge'})
        #   else
        #     "<b class='label bg-warning'>Inscripción Cerrada".html_safe
        #   end
        # end

        html_attributes do
          {'data-bs-original-title': ''}
        end
        pretty_value do

          current_user = bindings[:view]._current_user

          if current_user&.admin&.authorized_manage? 'School'
            bindings[:view].render(partial: "/schools/form_enabled_enroll", locals: {school: bindings[:object]})
          end
        end

      end
      fields :active_process do
        label 'Período Activo'
        queryable false
        filterable false
        searchable false
        sortable false

        # pretty_value do

        #   if bindings[:object].active_process
        #     bindings[:view].content_tag(:b, "#{bindings[:object].active_process.period.name}", {class: 'bg-success badge'})
        #   else
        #     "<b class='label bg-warning'>Sin Período Activo".html_safe
        #   end
        # end

        pretty_value do

          current_user = bindings[:view]._current_user
          admin = current_user.admin
          active = admin and admin.authorized_manage? 'School'

          if active
            bindings[:view].render(partial: "/schools/form_enabled_active", locals: {school: bindings[:object]})
          else
            value
          end
        end
      end

      field :download_all_grades do
        label 'Total Estudiantes'

        pretty_value do
          if bindings[:view]._current_user&.admin&.yo?
            bindings[:view].render(partial: "/schools/all_grades_link", locals: {school: bindings[:object]})
          else
            ApplicationController.helpers.label_status('bg-info', bindings[:object].grades.count)
          end
        end
      end 
    end

    show do
      field :description
      field :departaments do
        pretty_value do
          bindings[:view].render(template: '/departaments/index', locals: {departaments: bindings[:object].departaments.order(name: :asc)})
        end
      end

      # field :enable_dependents do
      #   label 'Activar Prelaciones'

      #   pretty_value do

      #     current_user = bindings[:view]._current_user
      #     admin = current_user.admin
      #     active = admin and admin.authorized_manage? 'School'

      #     if active
      #       bindings[:view].render(partial: "/schools/form_dependents", locals: {school: bindings[:object]})
      #     else
      #       value
      #     end
      #   end

      # end

      # field :enroll_process do

      #   # pretty_value do

      #   #   current_user = bindings[:view]._current_user
      #   #   admin = current_user.admin
      #   #   active = admin and admin.authorized_manage? 'School'

      #   #   if active
      #   #     bindings[:view].render(partial: "/schools/form_enabled_enroll", locals: {school: bindings[:object]})
      #   #   else
      #   #     value
      #   #   end
      #   # end

      # end

      # field :active_process do

      #   # pretty_value do

      #   #   current_user = bindings[:view]._current_user
      #   #   admin = current_user.admin
      #   #   active = admin and admin.authorized_manage? 'School'

      #   #   if true #active
      #   #     bindings[:view].render(partial: "/schools/form_enabled_active", locals: {school: bindings[:object]})
      #   #   else
      #   #     value
      #   #   end
      #   # end

      # end      

      # fields :study_plans, :periods, :areas
    end

    edit do
      field :faculty do
        read_only true
        pretty_value do
          value.short_name
        end
      end

      field :code do
        html_attributes do
          {:length => 3, :size => 3, :onInput => "$(this).val($(this).val().toUpperCase().replace(/[^A-Za-z]/g,''))"}
        end
      end
      field :name do
        html_attributes do
          {:onInput => "$(this).val($(this).val().toUpperCase())"}
        end
      end
      field :short_name do
        html_attributes do
          {:onInput => "$(this).val($(this).val().toUpperCase())"}
        end
      end

      # field :departaments

			field :bank_accounts do
				inline_edit false
				inline_add false
			end      
    end

    update do
      field :code do
        read_only true
      end
      field :name do
        read_only true
      end
      field :short_name do
        html_attributes do
          {:onInput => "$(this).val($(this).val().toUpperCase())"}
        end
      end
			field :bank_accounts do
				inline_edit false
				inline_add false
			end
    end

    export do
      fields :code, :name, :type_entity
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
      self.paper_trail_event = "¡#{object} registrada!"
    end  

    def paper_trail_destroy
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      self.paper_trail_event = "¡Escuela eliminada!"
    end

end
