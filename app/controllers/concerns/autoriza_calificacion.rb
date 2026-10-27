# Calificar (notas finales y parciales): el profesor de la sección mientras no la haya cerrado,
# o un admin que gestione secciones de esa escuela (el mismo criterio con que RailsAdmin muestra la planilla).
module AutorizaCalificacion
  extend ActiveSupport::Concern

  included do
    before_action :set_academic_record, only: %i[ update ]
    before_action :autorizar_calificacion!, only: %i[ update ]
  end

  private

  def autorizar_calificacion!
    section = @academic_record.section
    autorizado = if logged_as_admin?
                   current_admin.authorized_manage?('Section') and administra_escuela?(section.school&.id)
                 else
                   profesor_califica?(section)
                 end
    rechazar 'No autorizado para calificar esta sección' unless autorizado
  end

  def set_academic_record
    @academic_record = AcademicRecord.find(params[:id])
  end
end
