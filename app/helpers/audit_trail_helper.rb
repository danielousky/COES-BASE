module AuditTrailHelper
  # Método para obtener el icono según el tipo de evento
  def audit_event_icon(event)
    case event
    when 'create'
      'fa-plus-circle text-success'
    when 'update'
      'fa-edit text-warning'
    when 'destroy'
      'fa-trash text-danger'
    else
      'fa-info-circle text-info'
    end
  end

  # Método para obtener el icono según el tipo de registro
  def audit_item_type_icon(item_type)
    case item_type
    when 'User'
      'fa-user text-primary'
    when 'Student'
      'fa-graduation-cap text-success'
    when 'Admin'
      'fa-user-shield text-warning'
    when 'Teacher'
      'fa-chalkboard-teacher text-info'
    when 'Grade'
      'fa-id-card text-secondary'
    when 'EnrollAcademicProcess'
      'fa-clipboard-list text-primary'
    when 'AcademicRecord'
      'fa-book text-success'
    when 'Section'
      'fa-users text-warning'
    when 'Subject'
      'fa-book-open text-info'
    when 'AcademicProcess'
      'fa-calendar-alt text-primary'
    when 'PaymentReport'
      'fa-file-invoice-dollar text-success'
    else
      'fa-file text-muted'
    end
  end

  # Método para obtener el badge según el evento
  def audit_event_badge(event)
    case event
    when 'create'
      'badge bg-success'
    when 'update'
      'badge bg-warning'
    when 'destroy'
      'badge bg-danger'
    else
      'badge bg-info'
    end
  end

  # Método para formatear los cambios de manera legible
  def format_audit_changes(object_changes)
    return 'Sin cambios detallados' if object_changes.blank?

    begin
      changes = JSON.parse(object_changes)
      return 'Sin cambios detallados' unless changes.is_a?(Hash) && changes.any?

      changes.map do |key, change|
        if change.is_a?(Array) && change.length == 2
          old_val = change[0].nil? ? 'vacío' : change[0].to_s.truncate(30)
          new_val = change[1].nil? ? 'vacío' : change[1].to_s.truncate(30)
          "#{key.humanize}: #{old_val} → #{new_val}"
        else
          "#{key.humanize}: #{change.to_s.truncate(50)}"
        end
      end.join('<br>').html_safe
    rescue JSON::ParserError
      object_changes.truncate(100)
    end
  end

  # Método para obtener el nombre del usuario responsable
  def audit_user_name(whodunnit)
    return 'Sistema' if whodunnit.blank?

    user = User.find_by(id: whodunnit)
    if user
      "#{user.first_name} #{user.last_name} (#{user.ci})"
    else
      "Usuario ID: #{whodunnit}"
    end
  end

  # Método para obtener información detallada del usuario
  def audit_user_info(whodunnit)
    return { name: 'Sistema', details: 'Acción automática del sistema' } if whodunnit.blank?

    user = User.find_by(id: whodunnit)
    if user
      {
        name: "#{user.first_name} #{user.last_name}",
        details: "CI: #{user.ci} | Email: #{user.email}",
        user: user
      }
    else
      {
        name: "Usuario ID: #{whodunnit}",
        details: 'Usuario no encontrado',
        user: nil
      }
    end
  end

  # Método para obtener el tipo de evento en español
  def audit_event_name(event)
    case event
    when 'create'
      'Registro'
    when 'update'
      'Actualización'
    when 'destroy'
      'Eliminación'
    else
      event.humanize
    end
  end

  # Método para obtener el tipo de registro en español
  def audit_item_type_name(item_type)
    case item_type
    when 'User'
      'Usuario'
    when 'Student'
      'Estudiante'
    when 'Admin'
      'Administrador'
    when 'Teacher'
      'Docente'
    when 'Grade'
      'Expediente'
    when 'EnrollAcademicProcess'
      'Proceso Académico'
    when 'AcademicRecord'
      'Registro Académico'
    when 'Section'
      'Sección'
    when 'Subject'
      'Asignatura'
    when 'AcademicProcess'
      'Período Académico'
    when 'PaymentReport'
      'Reporte de Pago'
    else
      item_type.humanize
    end
  end

  # Método para generar un resumen de actividad
  def audit_activity_summary(version)
    event_name = audit_event_name(version.event)
    item_name = audit_item_type_name(version.item_type)
    user_name = audit_user_name(version.whodunnit)
    
    "#{event_name} de #{item_name} por #{user_name}"
  end

  # Método para obtener estadísticas de actividad por período
  def audit_period_stats(period = 30.days)
    start_date = period.ago
    
    {
      total: PaperTrail::Version.where(created_at: start_date..).count,
      by_event: PaperTrail::Version.where(created_at: start_date..).group(:event).count,
      by_type: PaperTrail::Version.where(created_at: start_date..).group(:item_type).count,
      by_user: PaperTrail::Version.where(created_at: start_date..).where.not(whodunnit: nil).group(:whodunnit).count
    }
  end

  # Método para generar un timeline de actividades
  def audit_timeline(versions, limit = 20)
    versions.limit(limit).map do |version|
      {
        id: version.id,
        date: version.created_at,
        event: version.event,
        item_type: version.item_type,
        user: audit_user_name(version.whodunnit),
        summary: audit_activity_summary(version),
        icon: audit_item_type_icon(version.item_type),
        badge: audit_event_badge(version.event)
      }
    end
  end

  # Método para filtrar actividades por tipo de usuario
  def filter_audit_by_user_type(versions, user_type)
    case user_type
    when 'student'
      versions.joins("LEFT JOIN students ON versions.item_id = students.user_id")
              .where("versions.item_type IN (?) OR students.user_id IS NOT NULL", 
                     ['Student', 'User', 'Grade', 'EnrollAcademicProcess', 'AcademicRecord'])
    when 'admin'
      versions.joins("LEFT JOIN admins ON versions.item_id = admins.user_id")
              .where("versions.item_type IN (?) OR admins.user_id IS NOT NULL", 
                     ['Admin', 'User', 'AcademicProcess', 'Section', 'Subject'])
    when 'teacher'
      versions.joins("LEFT JOIN teachers ON versions.item_id = teachers.user_id")
              .where("versions.item_type IN (?) OR teachers.user_id IS NOT NULL", 
                     ['Teacher', 'User', 'Section', 'AcademicRecord'])
    else
      versions
    end
  end
end

