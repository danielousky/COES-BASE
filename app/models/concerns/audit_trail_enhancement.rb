# Concern para mejorar la funcionalidad de auditoría con PaperTrail
module AuditTrailEnhancement
  extend ActiveSupport::Concern

  # Eventos específicos para estudiantes
  STUDENT_EVENTS = {
    user_registration: "Registro de Usuario",
    student_registration: "Registro como Estudiante", 
    login: "Inicio de Sesión",
    logout: "Cierre de Sesión",
    personal_data_update: "Actualización de Datos Personales",
    grade_registration: "Registro de Grado/Expediente",
    preenrollment: "Preinscripción en Período",
    subject_enrollment: "Inscripción en Asignatura",
    enrollment_confirmation: "Confirmación de Inscripción",
    subject_withdrawal: "Retiro de Materia",
    section_change: "Cambio de Sección",
    document_download: "Descarga de Documento",
    document_generation: "Generación de Documento"
  }.freeze

  # Eventos específicos para administradores
  ADMIN_EVENTS = {
    user_registration: "Registro de Usuario",
    admin_registration: "Registro como Administrador",
    login: "Inicio de Sesión",
    logout: "Cierre de Sesión",
    personal_data_update: "Actualización de Datos Personales",
    student_preenrollment: "Preinscripción de Estudiante",
    enrollment_approval: "Aprobación de Inscripción",
    enrollment_rejection: "Rechazo de Inscripción",
    grade_management: "Gestión de Expedientes",
    academic_process_management: "Gestión de Períodos Académicos",
    section_management: "Gestión de Secciones",
    qualification_management: "Gestión de Calificaciones",
    document_generation: "Generación de Documento",
    report_generation: "Generación de Reporte"
  }.freeze

  included do
    # Método para crear eventos personalizados
    def create_audit_event(event_type, details = {})
      event_name = case self.class.name
      when 'Student'
        STUDENT_EVENTS[event_type] || event_type.to_s.humanize
      when 'Admin'
        ADMIN_EVENTS[event_type] || event_type.to_s.humanize
      else
        event_type.to_s.humanize
      end

      # Crear el evento con detalles adicionales
      self.paper_trail_event = build_event_message(event_name, details)
    end

    # Método para registrar eventos de autenticación
    def audit_authentication_event(event_type, ip_address = nil, user_agent = nil)
      details = {}
      details[:ip_address] = ip_address if ip_address
      details[:user_agent] = user_agent if user_agent
      
      create_audit_event(event_type, details)
    end

    # Método para registrar eventos de documentos
    def audit_document_event(event_type, document_type, document_name = nil)
      details = {
        document_type: document_type,
        document_name: document_name
      }
      
      create_audit_event(event_type, details)
    end

    # Método para registrar eventos académicos
    def audit_academic_event(event_type, academic_details = {})
      create_audit_event(event_type, academic_details)
    end

    private

    def build_event_message(event_name, details)
      message = event_name
      
      if details.any?
        detail_parts = details.map do |key, value|
          case key
          when :ip_address
            "IP: #{value}"
          when :user_agent
            "Navegador: #{value.truncate(50)}"
          when :document_type
            "Tipo: #{value}"
          when :document_name
            "Documento: #{value}"
          when :subject_name
            "Asignatura: #{value}"
          when :section_name
            "Sección: #{value}"
          when :period_name
            "Período: #{value}"
          when :grade_name
            "Grado: #{value}"
          else
            "#{key.to_s.humanize}: #{value}"
          end
        end
        
        message += " (#{detail_parts.join(', ')})" if detail_parts.any?
      end
      
      message
    end
  end

  class_methods do
    # Método para obtener eventos recientes de un usuario
    def recent_audit_events(user_id, limit = 10)
      PaperTrail::Version.where(whodunnit: user_id.to_s)
                        .order(created_at: :desc)
                        .limit(limit)
    end

    # Método para obtener eventos por tipo
    def audit_events_by_type(item_type, limit = 50)
      PaperTrail::Version.where(item_type: item_type)
                        .order(created_at: :desc)
                        .limit(limit)
    end

    # Método para obtener eventos de estudiantes
    def student_audit_events(limit = 100)
      PaperTrail::Version.joins("LEFT JOIN students ON versions.item_id = students.user_id")
                        .where("versions.item_type IN (?) OR students.user_id IS NOT NULL", 
                               ['Student', 'User', 'Grade', 'EnrollAcademicProcess', 'AcademicRecord'])
                        .order(created_at: :desc)
                        .limit(limit)
    end

    # Método para obtener estadísticas de auditoría
    def audit_statistics(days = 30)
      start_date = days.days.ago
      
      {
        total_events: PaperTrail::Version.where(created_at: start_date..).count,
        user_registrations: PaperTrail::Version.where(item_type: 'User', event: 'create', created_at: start_date..).count,
        student_registrations: PaperTrail::Version.where(item_type: 'Student', event: 'create', created_at: start_date..).count,
        logins: PaperTrail::Version.where("object_changes LIKE ?", '%sign_in_count%').where(created_at: start_date..).count,
        academic_events: PaperTrail::Version.where(item_type: ['Grade', 'EnrollAcademicProcess', 'AcademicRecord'], created_at: start_date..).count,
        document_events: PaperTrail::Version.where("object_changes LIKE ? OR object_changes LIKE ?", '%document%', '%download%').where(created_at: start_date..).count
      }
    end
  end
end

