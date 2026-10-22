# Datos del mapa de prelaciones de una escuela (vista Estructura del plan de estudio).
# La regla de oferta no se replica aquí: la del estudiante sale de Grade#asignaturas_ofertables_segun_dependencia.
class MapaPrelaciones
  def initialize(school)
    @school = school
  end

  def datos
    materias = @school.subjects.to_a
    prelaciones = SubjectLink.where(prelate_subject_id: materias.map(&:id)).includes(:prelate_subject, :depend_subject).to_a
    # Prerrequisitos de otra escuela: se muestran para que la prelación no quede apuntando a la nada
    externas = prelaciones.map(&:depend_subject).reject { |previa| previa.school_id == @school.id }.uniq

    {
      materias: materias.map { |materia| datos_materia(materia) } + externas.map { |materia| datos_materia(materia, externa: true) },
      prelaciones: prelaciones.map(&:datos_mapa)
    }
  end

  def oferta(grade)
    {
      estudiante: grade.student.user.reverse_name,
      ci: grade.student.user.ci,
      aprobadas: grade.academic_records.aprobado.joins(:subject).pluck('subjects.id').uniq,
      ofertables: grade.asignaturas_ofertables_segun_dependencia.ids
    }
  end

  # Simulador de CE: la oferta de hoy en el mapa más la capa del período
  # (lo que de verdad le aparecería al inscribirse y lo que ya inscribió)
  def simulacion(grade, academic_process)
    oferta_real = OfertaInscripcion.new(grade, academic_process, como_estudiante: true)
    datos = oferta(grade)
    datos[:ofertables] = @school.subjects.where.not(id: datos[:aprobadas]).ids unless grade.study_plan.por_dependencia?
    ofertadas = OfertaInscripcion.con_secciones(oferta_real.cursos)
    datos.merge(periodo: {
      nombre: academic_process.process_name,
      ofertadas: ofertadas.map(&:subject_id),
      sin_cupo: ofertadas.select { |curso| OfertaInscripcion.secciones_elegibles(curso, grade, nil).empty? }.map(&:subject_id),
      # Para simular al tocar materias: todo lo ofertado con sección, sin filtrar prelaciones ni aprobadas
      programadas: OfertaInscripcion.con_secciones(academic_process.courses.offers.includes(:sections)).map(&:subject_id),
      inscritas: grade.academic_records.where.not(status: :retirado).joins(section: :course)
                      .where(courses: {academic_process_id: academic_process.id}).pluck('courses.subject_id')
    })
  end

  private

  def datos_materia(materia, externa: false)
    {id: materia.id, codigo: materia.code, nombre: materia.name, semestre: materia.ordinal.to_i,
     creditos: materia.unit_credits, externa: externa}
  end
end
