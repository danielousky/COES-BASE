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

  private

  def datos_materia(materia, externa: false)
    {id: materia.id, codigo: materia.code, nombre: materia.name, semestre: materia.ordinal.to_i,
     creditos: materia.unit_credits, externa: externa}
  end
end
