# ¿Puede el estudiante inscribirse hoy por su cuenta en este período? Y si no, por qué.
# Las condiciones son las de la pantalla del estudiante (enroll_academic_processes/_new_student), que las usa
# desde aquí; el simulador de CE lee el mismo #estado, así que ambos dicen siempre lo mismo.
class AccesoInscripcion
  MENSAJES = {
    proceso_cerrado: 'El período no tiene la inscripción abierta para su plan',
    es_su_hora: 'Puede inscribirse ahora: está dentro de su cita horaria',
    directa: 'Puede inscribirse ahora: el período no usa cita horaria',
    cita_futura: 'Todavía no: su cita horaria aún no llega',
    cita_vencida: 'Ya no: su cita horaria pasó',
    sin_cita: 'No: el período usa cita horaria y no tiene una asignada',
    ya_inscrito: 'Ya completó su inscripción en este período',
    reglamento: 'No: por su estado de permanencia sólo ve el reglamento',
    por_control_estudio: 'No: por su estado de permanencia debe inscribirlo Control de Estudio',
    permanencia_impide: 'No: su estado de permanencia le impide inscribirse',
    no_inscrito_anterior: 'No: no se inscribió en el período anterior',
    contactar_control_estudio: 'No: debe pedir a Control de Estudio que le permita preinscribirse'
  }.freeze

  attr_reader :grade, :academic_process, :inscripcion

  def initialize(grade, academic_process)
    @grade = grade
    @academic_process = academic_process
    @inscripcion = grade.enroll_academic_processes.of_academic_process(academic_process.id).first
  end

  def estado
    return :proceso_cerrado unless proceso_abierto?

    if via_regular?
      return :ya_inscrito unless pendiente?
      return :directa unless con_cita_horaria?
      return :sin_cita unless tiene_cita?
      return :es_su_hora if es_su_hora?
      return :cita_futura if cita_futura?

      :cita_vencida
    elsif reglamento?
      :reglamento
    elsif por_control_estudio?
      :por_control_estudio
    elsif permanencia_impide?
      :permanencia_impide
    elsif no_inscrito_en_el_anterior?
      :no_inscrito_anterior
    else
      :contactar_control_estudio
    end
  end

  def habilitado?
    %i[es_su_hora directa].include? estado
  end

  def mensaje
    MENSAJES[estado]
  end

  # Igual que la pantalla del estudiante: sólo procesos de su modalidad con la inscripción abierta
  def proceso_abierto?
    academic_process.enroll? and academic_process.modality.eql?(grade.study_plan_modality)
  end

  def via_regular?
    inscripcion&.reservado? or grade.valid_to_enroll_in(academic_process)
  end

  def pendiente?
    inscripcion.nil? or inscripcion.reservado?
  end

  def con_cita_horaria?
    academic_process.enrollment_days.any?
  end

  def tiene_cita?
    grade.has_a_appointment_time?
  end

  def es_su_hora?
    grade.can_enroll_by_apponintment?
  end

  def cita_futura?
    grade.enroll_is_in_future? and inscripcion.nil?
  end

  def reglamento?
    %w[articulo3 articulo6 articulo7].include? grade.current_permanence_status
  end

  def por_control_estudio?
    %w[intercambio egresado egresado_doble_titulo].include? grade.current_permanence_status
  end

  def permanencia_impide?
    %w[desertor permiso_para_no_cursar].include? grade.current_permanence_status
  end

  def no_inscrito_en_el_anterior?
    anterior = academic_process.process_before
    anterior and !grade.enroll_academic_processes.of_academic_process(anterior.id).any?
  end
end
