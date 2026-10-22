require "test_helper"

# OfertaInscripcion: la oferta del formulario de inscripción, extraída de la vista sin cambiar la regla.
#   - el estudiante sólo ve lo que cumple prelaciones (plan por dependencia); CE ve todo el período
#   - nunca se ofertan aprobadas ni cursos que no están en oferta
#   - PCI: cursos de otras escuelas de pregrado del mismo lapso ofertados como PCI
class OfertaInscripcionTest < ActiveSupport::TestCase
  setup do
    @uid = SecureRandom.hex(4)
    faculty = Faculty.create!(name: "Fac OI #{@uid}", code: "FOI#{@uid}", contact_email: "foi#{@uid}@test.com", coes_boss_name: "Jefe #{@uid}")
    @school = School.create!(name: "Esc OI #{@uid}", code: "EOI#{@uid}", faculty: faculty)
    @otra = School.create!(name: "Otra OI #{@uid}", code: "OOI#{@uid}", faculty: faculty)
    @plan = StudyPlan.create!(code: "SPOI#{@uid}", name: "Plan OI #{@uid}", school: @school, structure: :por_dependencia)
    @tipo = SubjectType.create!(code: "OI#{("a".."z").to_a.sample(8).join}", name: "Oblig #{@uid}")

    tipo_periodo = PeriodType.create!(code: "O#{@uid}", name: "Período #{@uid}")
    periodo_anterior = Period.create!(year: 2024, period_type: tipo_periodo)
    @periodo = Period.create!(year: 2025, period_type: tipo_periodo)
    @anterior = AcademicProcess.create!(school: @school, period: periodo_anterior, max_credits: 24, max_subjects: 6)
    @proceso = AcademicProcess.create!(school: @school, period: @periodo, max_credits: 24, max_subjects: 6, process_before: @anterior)

    @uno = materia('Uno', 1)
    @dos = materia('Dos', 2)          # exige Uno
    @tres = materia('Tres', 3)        # exige Dos
    @libre = materia('Libre', 1)      # sin prelaciones
    @no_ofertada = materia('Cerrada', 1)
    SubjectLink.create!(prelate_subject: @dos, depend_subject: @uno)
    SubjectLink.create!(prelate_subject: @tres, depend_subject: @dos)

    [@uno, @dos, @tres, @libre].each { |m| Course.create!(subject: m, academic_process: @proceso) }
    Course.create!(subject: @no_ofertada, academic_process: @proceso, offer: false)

    user = User.create!(ci: "#{rand(10**8)}", email: "oi#{@uid}@test.com", first_name: 'Ana', last_name: 'Oferta',
                        password: 'password123', updated_password: true)
    @grade = Grade.create!(student: Student.create!(user: user), study_plan: @plan,
                           admission_type: AdmissionType.create!(name: "Adm #{@uid}", code: "AOI#{@uid}"))
  end

  def materia(nombre, ordinal, school: @school)
    area = Area.create!(name: "Area #{nombre} #{@uid}", school: school)
    dpto = Departament.create!(name: "Dpto #{nombre} #{@uid}", school: school).tap { |d| d.areas << area }
    Subject.create!(code: "OI#{nombre}#{@uid}", name: "#{nombre} #{@uid}", ordinal: ordinal, subject_type: @tipo,
                    qualification_type: :numerica, unit_credits: 3, area: area, departament: dpto, school: school)
  end

  def aprobar(materia)
    curso = Course.create!(subject: materia, academic_process: @anterior)
    seccion = Section.create!(course: curso, code: "A#{materia.id}", capacity: 30, modality: :nota_final, qualified: false)
    inscripcion = @grade.enroll_academic_processes.find_or_create_by!(academic_process: @anterior) do |eap|
      eap.enroll_status = :confirmado
      eap.permanence_status = :regular
    end
    AcademicRecord.create!(section: seccion, enroll_academic_process: inscripcion, status: :sin_calificar).update_columns(status: :aprobado)
  end

  def materias(cursos)
    cursos.map(&:subject)
  end

  test "el estudiante sólo ve lo que cumple prelaciones; CE ve toda la oferta del período" do
    assert_equal [@libre, @uno].sort_by(&:code), materias(OfertaInscripcion.new(@grade, @proceso, como_estudiante: true).cursos)
    assert_equal [@dos, @libre, @tres, @uno].sort_by(&:code), materias(OfertaInscripcion.new(@grade, @proceso, como_estudiante: false).cursos)
  end

  test "al aprobar un prerrequisito se abre lo siguiente y la aprobada sale de la oferta" do
    aprobar(@uno)
    assert_equal [@dos, @libre].sort_by(&:code), materias(OfertaInscripcion.new(@grade, @proceso, como_estudiante: true).cursos)
    assert_not_includes materias(OfertaInscripcion.new(@grade, @proceso, como_estudiante: false).cursos), @uno
  end

  test "un plan sin restricciones no filtra prelaciones" do
    @plan.update!(structure: :sin_restricciones)
    assert_equal 4, OfertaInscripcion.new(@grade.reload, @proceso, como_estudiante: true).cursos.size
  end

  test "PCI: cursos de otra escuela de pregrado del mismo lapso ofertados como PCI" do
    proceso_otra = AcademicProcess.create!(school: @otra, period: @periodo, max_credits: 24, max_subjects: 6)
    pci = Course.create!(subject: materia('Pci', 1, school: @otra), academic_process: proceso_otra, offer_as_pci: true)
    Course.create!(subject: materia('NoPci', 1, school: @otra), academic_process: proceso_otra, offer_as_pci: false)

    assert_equal [pci], OfertaInscripcion.new(@grade, @proceso, como_estudiante: true).pcis
  end
end
