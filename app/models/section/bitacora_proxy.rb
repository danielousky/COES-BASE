class Section
  class BitacoraProxy
    attr_reader :version

    def initialize(version, user_lookup: {}, item_cache: {})
      @version = version
      @user_lookup = user_lookup
      @item_cache = item_cache
    end

    # --- Delegaciones basicas al PaperTrail::Version ---

    def id
      @version.id
    end

    def created_at
      @version.created_at
    end

    def whodunnit
      @version.whodunnit
    end

    def event
      @version.event
    end

    def item_type
      @version.item_type
    end

    def item_id
      @version.item_id
    end

    def object_changes
      @version.object_changes
    end

    def ip
      @version.respond_to?(:ip) ? @version.ip : nil
    end

    def user_agent
      @version.respond_to?(:user_agent) ? @version.user_agent : nil
    end

    # --- Lookup de usuario ---

    def user
      return @user if defined?(@user)
      key = @version.whodunnit.to_s
      @user = @user_lookup[key] if key.match?(/\A\d+\z/)
      @user
    end

    def user_label
      if user
        if user.respond_to?(:full_name) && user.full_name.to_s.strip.present?
          user.full_name
        elsif user.respond_to?(:reverse_name)
          user.reverse_name
        else
          user.try(:name)
        end
      elsif whodunnit.present?
        whodunnit.to_s
      else
        'Sistema'
      end
    end

    def user_ci
      user&.ci
    end

    def student_ci_fullname
      u = related_student_user
      return nil unless u
      if u.respond_to?(:ci_fullname)
        u.ci_fullname
      elsif u.respond_to?(:reverse_name)
        "#{u.try(:ci)}: #{u.reverse_name}".strip.sub(/\A:\s*/, '')
      else
        u.try(:name)
      end
    end

    # --- Item cacheado ---

    def item
      @item ||= @item_cache.dig(item_type, item_id)
    end

    def related_academic_record
      return item if item_type == 'AcademicRecord'
      item&.try(:academic_record) if item_type == 'Qualification'
    end

    def related_student_user
      ar = related_academic_record
      ar&.try(:user)
    end

    def student_ci
      related_student_user&.ci
    end

    def student_label
      u = related_student_user
      return nil unless u
      u.respond_to?(:reverse_name) ? u.reverse_name : u.try(:name)
    end

    # --- Normalizacion del evento ---

    def event_kind
      raw = @version.event.to_s
      case raw
      when 'create'  then :creacion
      when 'update'  then :modificacion
      when 'destroy' then :eliminacion
      else
        downcased = raw.downcase
        if downcased.match?(/elimina|destruid|borrad/)
          :eliminacion
        elsif downcased.match?(/actualiz|cambió|cambio|modifica|calificad/)
          :modificacion
        elsif downcased.match?(/registrad|cread|nuev/)
          :creacion
        else
          :otro
        end
      end
    end

    # --- Resumen del evento ---

    def summary_title
      case item_type
      when 'Qualification'   then qualification_summary
      when 'AcademicRecord'  then academic_record_summary
      when 'Section'         then section_summary
      when 'SectionTeacher'  then section_teacher_summary
      else
        event.to_s.presence || event_kind.to_s.titleize
      end
    end

    def summary_detail
      return nil if %w[Qualification AcademicRecord].include?(item_type)
      changes_summary
    end

    def badge_class
      case event_kind
      when :creacion     then 'bg-success'
      when :modificacion then 'bg-primary'
      when :eliminacion  then 'bg-danger'
      else 'bg-secondary'
      end
    end

    def badge_label
      case event_kind
      when :creacion     then 'Creacion'
      when :modificacion then 'Modificacion'
      when :eliminacion  then 'Eliminacion'
      else 'Evento'
      end
    end

    def device_label
      Section::UserAgentParser.call(user_agent)
    end

    def parsed_changes
      return {} unless @version.object_changes.present?
      permitted = [Time, Date, Symbol, ActiveSupport::TimeWithZone, ActiveSupport::Duration, BigDecimal]
      begin
        data = YAML.safe_load(@version.object_changes, permitted_classes: permitted, aliases: true) || {}
      rescue NameError, ArgumentError
        data = YAML.safe_load(@version.object_changes, permitted_classes: [Time, Date, Symbol]) || {}
      end
      data.reject { |k, _| %w[updated_at created_at].include?(k) }
    rescue StandardError
      {}
    end

    private

    def qualification_summary
      changes = parsed_changes
      value_change = changes['value']

      case event_kind
      when :creacion
        value = value_change.is_a?(Array) ? value_change.last : item&.try(:value)
        "Calificada con #{format_grade(value)}"
      when :modificacion
        if value_change.is_a?(Array)
          prev_val, curr_val = value_change
          "Calificacion modificada: #{format_grade(prev_val)} -> #{format_grade(curr_val)}"
        else
          event.to_s.presence || 'Calificacion modificada'
        end
      when :eliminacion
        'Calificacion eliminada'
      else
        event.to_s.presence || 'Evento de calificacion'
      end
    end

    def academic_record_summary
      changes = parsed_changes
      status_change = changes['status']

      if event_kind == :eliminacion
        return 'Registro academico eliminado'
      end

      if status_change.is_a?(Array)
        _, new_val = status_change
        case new_val.to_i
        when 3 then 'Retirada'
        when 4 then 'Perdida por inasistencia (PI)'
        when 1 then 'Marcada como aprobada'
        when 2 then 'Marcada como aplazada'
        else
          event.to_s.presence || "Cambio de estado a #{new_val}"
        end
      else
        event.to_s.presence || 'Cambio en registro academico'
      end
    end

    def section_summary
      changes = parsed_changes

      case event_kind
      when :creacion
        'Seccion creada'
      when :eliminacion
        'Seccion eliminada'
      else
        if changes.key?('qualified')
          _, new_val = changes['qualified']
          return new_val ? 'Seccion marcada como calificada' : 'Seccion desmarcada (abierta para calificar)'
        end
        if changes.key?('teacher_id')
          prev_val, new_val = changes['teacher_id']
          if prev_val.nil? && new_val.present?
            teacher_name = resolve_teacher_name(new_val)
            return "Profesor asignado: #{teacher_name}"
          elsif prev_val.present? && new_val.nil?
            teacher_name = resolve_teacher_name(prev_val)
            return "Profesor removido: #{teacher_name}"
          elsif prev_val != new_val
            prev_name = resolve_teacher_name(prev_val)
            new_name  = resolve_teacher_name(new_val)
            return "Profesor cambiado: #{prev_name} -> #{new_name}"
          end
        end
        event.to_s.presence || 'Seccion actualizada'
      end
    end

    def section_teacher_summary
      case event_kind
      when :creacion
        "Profesor asignado: #{related_teacher_name}"
      when :eliminacion
        "Profesor removido: #{related_teacher_name}"
      else
        event.to_s.presence || 'Cambio en asignacion de profesor'
      end
    end

    def related_teacher_name
      return nil unless item
      teacher = item.try(:teacher)
      safe_teacher_description(teacher) || teacher&.try(:user)&.try(:reverse_name) || teacher&.to_s
    end

    def resolve_teacher_name(id)
      return 'sin asignar' if id.blank?
      teacher = Teacher.find_by(user_id: id) || Teacher.find_by(id: id)
      desc = safe_teacher_description(teacher)
      return desc if desc.present?
      user = User.find_by(id: id)
      user&.try(:reverse_name) || "##{id}"
    end

    def safe_teacher_description(teacher)
      return nil unless teacher&.respond_to?(:description)
      teacher.description
    rescue StandardError
      teacher.try(:user)&.try(:reverse_name)
    end

    def format_grade(value)
      return '--' if value.nil?
      return 'PI' if value.to_i == 0
      num = value.is_a?(Numeric) ? value : value.to_f
      num == num.to_i ? num.to_i.to_s : num.to_s
    end

    def changes_summary
      changes = parsed_changes
      return nil if changes.empty?
      changes.map do |field, (prev_val, new_val)|
        "#{field}: #{prev_val.inspect} -> #{new_val.inspect}"
      end.join(' | ')
    end
  end
end
