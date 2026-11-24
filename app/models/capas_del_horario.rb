# Lo que la grilla del panel de la Programación muestra alrededor del horario de una sección (23-nov). Daniel: «ver
# como información los horarios del profesor y, en otro tono, los de las otras secciones». Son tres capas, todas del
# mismo período:
#
#   profesor     las otras clases del profesor, en cualquier escuela, también donde es profesor secundario. Si un
#                bloque las pisa, la grilla lo avisa (ChoqueDelProfesor), salvo con las que se dictan juntas
#   asignatura   las otras secciones de la asignatura
#   semestre     las otras asignaturas del mismo semestre (o año) de la escuela, y las que cursaron junto con esta 5
#                estudiantes o más el mismo período del año anterior. Si todas las secciones de una de esas chocan con
#                todas las de esta asignatura, quien curse las dos no tiene cómo: la grilla también lo dice
#
# En producción, 2026-02: un semestre tiene 10 bloques de mediana y 31 en el p90. De las asignaturas que se cursaron
# juntas en 2025-02, 13 pares chocan sin remedio, y esos pares los cursaron juntos 117 estudiantes.
#
# Lo que no mira todavía: los profesores secundarios de la sección que se edita, las aulas, las menciones (0 cargadas)
# y los procesos anuales, que viven en un período 02 y siguen durante el 01 siguiente.
class CapasDelHorario
  MINIMO_JUNTOS = 5    # estudiantes en común para «se cursó junto»
  MAXIMO_JUNTOS = 12   # de esas asignaturas, las que más estudiantes tuvieron en común

  def initialize(seccion, profesor_id: seccion.teacher_id)
    @seccion = seccion
    @curso = seccion.course
    @proceso = @curso.academic_process
    @profesor_id = profesor_id.presence&.to_i
  end

  # «profesor_guardado» y «decidido», por si el panel vuelve sin guardar: con qué profesor está guardada (sus choques
  # de antes solo se avisan) y lo que ya se había decidido en el aviso.
  def para_grilla
    {profesor: profesor, asignatura: asignatura, semestre: semestre, juntas: juntas,
     profesor_guardado: @seccion.teacher_id_in_database, decidido: @seccion.decidido_en_el_aviso}
  end

  # Las otras clases del profesor en el período. «grupo» es el número de las que se dictan juntas: la grilla lo usa para
  # saber cuáles se juntan con una de ellas.
  def profesor
    docente = @profesor_id && Teacher.includes(:user).find_by(user_id: @profesor_id)
    return unless docente

    secciones = secciones_del_profesor(@profesor_id).map do |s|
      escuela = s.course.academic_process.school
      {id: s.id, codigo: s.code, asignatura: s.course.subject.name, grupo: s.dictado_conjunto,
       escuela: (escuela.short_name || escuela.code if escuela.id != @proceso.school_id), bloques: bloques_de(s)}
    end
    {id: @profesor_id, nombre: nombre_del_profesor(docente), periodo: @proceso.period.name, secciones: secciones}
  end

  def asignatura
    @curso.sections.where.not(id: @seccion.id).preload(timetable: :timeblocks, teacher: :user)
          .sort_by { |s| Section.orden_del_codigo(s.code) }
          .map { |s| {id: s.id, codigo: s.code, profesor: s.teacher&.user&.reverse_name, bloques: bloques_de(s)} }
  end

  # Solo las asignaturas que ya tienen algún horario cargado. «semestre»: es del mismo semestre que esta; «juntos»:
  # cuántos estudiantes la cursaron junto con esta en el período anterior.
  def semestre
    juntos = cursadas_junto
    del_semestre = ordinal.positive? ? cursos_de_la_escuela.where(subjects: {ordinal: ordinal}).pluck(:subject_id) : []
    materias = cursos_de_la_escuela.where(subject_id: del_semestre | juntos.keys)
                                   .preload(:subject, sections: {timetable: :timeblocks}).filter_map do |curso|
      secciones = curso.sections.map { |s| {id: s.id, codigo: s.code, bloques: bloques_de(s)} }
      next if secciones.none? { |s| s[:bloques].any? }

      {id: curso.subject_id, nombre: curso.subject.name, semestre: del_semestre.include?(curso.subject_id),
       juntos: juntos[curso.subject_id].to_i, secciones: secciones}
    end
    {rotulo: rotulo_del_semestre, anterior: periodo_anterior&.name,
     materias: materias.sort_by { |m| [-m[:juntos], m[:nombre]] }}
  end

  # Las que ya se dictan junto con esta (sections.dictado_conjunto).
  def juntas
    return [] unless @seccion.persisted?

    @seccion.juntas.preload(course: :subject).map { |s| {id: s.id, texto: "#{s.course.subject.name} (#{s.code})"} }
  end

  # Los choques del profesor que trae el cambio: los que habrá al guardar y no había antes, sin los que el asistente
  # aceptó con «Guardar igual» («excepto», ids de secciones). Hay secciones que ya chocaban (87 pares en 2026-02), y
  # corregirles el cupo no debe pedir nada. Un texto por cada sección con que choca.
  def choques_nuevos(excepto: [])
    return [] unless @seccion.teacher_id

    antes = @seccion.new_record? ? {} : choques(@seccion.teacher_id_in_database, bloques_guardados, @seccion.juntas.ids)
    nuevos = choques(@seccion.teacher_id, bloques_al_guardar, @seccion.juntas_al_guardar).except(*antes.keys, *excepto)
    return [] if nuevos.empty?

    nombre = nombre_del_profesor(Teacher.includes(:user).find_by(user_id: @seccion.teacher_id))
    nuevos.values.map do |suyo|
      "#{nombre} ya tiene clase a esa hora: #{suyo.descripcion_del_choque}. Mueva el bloque, márquelas como «Se " \
        'dictan juntas» o elija «Guardar igual».'
    end
  end

  private

  # «ROBERTO RUIZ LUIGI»: en el aviso se lee mejor que «RUIZ LUIGI, ROBERTO», como sale en el buscador.
  def nombre_del_profesor(docente)
    docente && "#{docente.user.first_name} #{docente.user.last_name}".squish
  end

  def secciones_del_periodo
    Section.joins(course: :academic_process).where(academic_processes: {period_id: @proceso.period_id})
           .where.not(id: @seccion.id)
  end

  def secciones_del_profesor(profesor_id)
    secundario = 'SELECT section_id FROM sections_teachers WHERE teacher_id = :p'
    secciones_del_periodo.where("sections.teacher_id = :p OR sections.id IN (#{secundario})", p: profesor_id)
      .preload(timetable: :timeblocks, course: [:subject, {academic_process: :school}])
      .sort_by { |s| [s.course.subject.name, Section.orden_del_codigo(s.code)] }
  end

  # La sección con que choca, con el primer bloque suyo que pisa uno de estos: {id de la sección => bloque}.
  def choques(profesor_id, bloques, juntas)
    return {} if profesor_id.nil? || bloques.empty?

    secciones_del_profesor(profesor_id).reject { |s| juntas.include?(s.id) }.each_with_object({}) do |otra, encontrados|
      suyo = otra.timetable&.timeblocks&.find { |b| bloques.any? { |mio| mio.se_pisa_con?(b) } }
      encontrados[otra.id] = suyo if suyo
    end
  end

  # Los que tendrá la sección al guardar: los del formulario, sin los que se van a borrar.
  def bloques_al_guardar
    horario = @seccion.timetable
    return [] if horario.nil? || horario.marked_for_destruction?

    horario.timeblocks.reject(&:marked_for_destruction?)
  end

  def bloques_guardados
    Timeblock.joins(:timetable).where(timetables: {section_id: @seccion.id}).to_a
  end

  # Como en Timeblock.para_grilla: «19:30», en hora del día. La fecha de las 8 pm en adelante no importa aquí.
  def bloques_de(seccion)
    (seccion.timetable&.timeblocks || []).sort_by { |b| [Timeblock.days[b.day], b.inicio_en_minutos] }.map do |b|
      {dia: b.day, inicio: b.start_time.strftime('%H:%M'), fin: b.end_time.strftime('%H:%M'), aula: b.classroom.to_s}
    end
  end

  # Los cursos de la escuela en el período, en cualquiera de sus procesos (Educación tiene el semestral y el de
  # componente), sin este.
  def cursos_de_la_escuela
    Course.joins(:academic_process, :subject)
          .where(academic_processes: {period_id: @proceso.period_id, school_id: @proceso.school_id}).where.not(id: @curso.id)
  end

  # {asignatura => estudiantes}: las que se inscribieron junto con esta en el período anterior de la misma época del
  # año (para 2026-02, el 2025-02).
  def cursadas_junto
    return {} unless periodo_anterior

    inscritos = AcademicRecord.joins(section: {course: :academic_process})
                              .where(academic_processes: {period_id: periodo_anterior.id})
                              .where(courses: {subject_id: @curso.subject_id}).select(:enroll_academic_process_id)
    cuenta = 'COUNT(DISTINCT academic_records.enroll_academic_process_id)'
    AcademicRecord.joins(section: :course).where(enroll_academic_process_id: inscritos)
                  .where.not(courses: {subject_id: @curso.subject_id}).group('courses.subject_id')
                  .having("#{cuenta} >= ?", MINIMO_JUNTOS).order(Arel.sql("#{cuenta} DESC")).limit(MAXIMO_JUNTOS)
                  .pluck('courses.subject_id', Arel.sql(cuenta)).to_h
  end

  def periodo_anterior
    return @periodo_anterior if defined?(@periodo_anterior)

    periodo = @proceso.period
    @periodo_anterior = Period.where(period_type_id: periodo.period_type_id).where('year < ?', periodo.year)
                              .order(year: :desc).first
  end

  def ordinal
    @curso.subject.ordinal.to_i
  end

  # «Semestre 3» o «Año 2», según el proceso; las de ordinal 0 (electivas) no tienen semestre.
  def rotulo_del_semestre
    return 'Se cursa junto' unless ordinal.positive?

    "#{@proceso.Anual? ? 'Año' : 'Semestre'} #{ordinal}"
  end
end
