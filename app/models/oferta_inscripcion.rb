# Lo que COES le oferta a un expediente al inscribirse en un período.
# Es la única fuente: la usan el formulario de inscripción y el simulador de CE, para que nunca difieran.
#
# como_estudiante: el filtro de prelaciones sólo se aplica cuando inscribe el propio estudiante;
# CE (sesión admin) ve toda la oferta del período para poder inscribir excepciones.
#
# Pendiente: en IDIO, ofertar sólo los idiomas de la combinación del estudiante (departament1/departament2).
# La vista lo tenía esbozado y apagado con `if false`; cuando se haga, va aquí.
class OfertaInscripcion
  attr_reader :grade, :academic_process

  def initialize(grade, academic_process, como_estudiante:)
    @grade = grade
    @academic_process = academic_process
    @como_estudiante = como_estudiante
  end

  # Cursos de la escuela, ordenados por código de asignatura
  def cursos
    @cursos ||= begin
      cursos = academic_process.courses.offers
      cursos = cursos.where(subject_id: grade.asignaturas_ofertables_segun_dependencia.ids) if filtra_prelaciones?
      aprobadas_ids = grade.subjects_approved_ids
      cursos = cursos.joins(:subject).where("subjects.id NOT IN (#{aprobadas_ids.join(',')})") if aprobadas_ids&.any?
      cursos.order_by_subject_code.uniq
    end
  end

  # Cursos de otras escuelas de pregrado del mismo lapso ofertados como PCI
  def pcis
    @pcis ||= academic_process.period.courses.joins(:school).where("schools.id != '?'", grade.school.id)
                              .where(schools: {type_entity: :pregrado}).pcis.order_by_subject_code.uniq
  end

  # Como la lista del estudiante (_courses_offer): un curso sin secciones no se le muestra
  def self.con_secciones(cursos)
    cursos.select { |curso| curso.sections.any? }
  end

  # Secciones que el estudiante puede elegir en un curso (_courses_offer): con cupo o la que ya tiene.
  # OJO: has_academic_record? espera el id de un AcademicRecord y recibe el student_id, como siempre lo hizo la vista;
  # en la práctica la sección propia entra por section_id.
  def self.secciones_elegibles(curso, grade, section_id)
    curso.sections.select { |seccion| seccion.has_capacity? or seccion.has_academic_record? grade.student_id or seccion.id.eql? section_id }
  end

  private

  def filtra_prelaciones?
    @como_estudiante and grade.study_plan.por_dependencia?
  end
end
