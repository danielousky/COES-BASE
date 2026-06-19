require "test_helper"

# Prueba de EnrollAcademicProcess.reservar_cupo a NIVEL DE MODELO (sin HTTP).
# Esta es la ganancia de mover la lógica de negocio fuera del controller:
# las reglas (liberar/reservar, capacidad, transacción + lock) ahora son
# unit-testeables sin pasar por la acción reserve_space.
class ReservarCupoTest < ActiveSupport::TestCase
  def setup
    @uid       = SecureRandom.hex(4)
    @uid_alpha = (("a".."z").to_a.sample(8)).join

    @faculty = Faculty.create!(name: "Fac RC #{@uid}", code: "FRC#{@uid}",
                               contact_email: "frc#{@uid}@test.com", coes_boss_name: "Jefe #{@uid}")
    @school  = School.create!(name: "Esc RC #{@uid}", code: "ERC#{@uid}", faculty: @faculty)
    @plan    = StudyPlan.create!(code: "SPRC#{@uid}", name: "Plan RC #{@uid}", school: @school)
    @adm     = AdmissionType.create!(name: "Adm RC #{@uid}", code: "ARC#{@uid}")
    @ptype   = PeriodType.create!(code: "U#{@uid}", name: "Único #{@uid}")
    @period  = Period.create!(year: 2025, period_type: @ptype)
    @ap      = AcademicProcess.create!(school: @school, period: @period, max_credits: 24, max_subjects: 6)

    @stype = SubjectType.create!(code: "OB#{@uid_alpha}", name: "Oblig RC #{@uid}")
    @area  = Area.create!(name: "Area RC #{@uid}", school: @school)
    @dept  = Departament.create!(name: "Dpto RC #{@uid}", school: @school)
    @dept.areas << @area
    @subject = Subject.create!(code: "MAT#{@uid}", name: "Mate RC #{@uid}", ordinal: 1,
                               subject_type: @stype, qualification_type: :numerica, unit_credits: 4,
                               area: @area, departament: @dept, school: @school)
    @course  = Course.create!(subject: @subject, academic_process: @ap, offer_as_pci: false)
    @section = Section.create!(course: @course, code: "S1", capacity: 30, modality: :nota_final, qualified: false)

    @user    = User.create!(ci: "RC#{@uid}#{rand(10**6)}", email: "rc#{@uid}@test.com",
                            first_name: "Est", last_name: "RC", password: "password123", updated_password: true)
    @student = Student.create!(user: @user)
    @grade   = Grade.create!(student: @student, study_plan: @plan, admission_type: @adm,
                             current_permanence_status: :regular)
  end

  def reservar(section_id:, course_id: @course.id)
    EnrollAcademicProcess.reservar_cupo(grade_id: @grade.id, academic_process_id: @ap.id,
                                        section_id: section_id, course_id: course_id)
  end

  test "reserva crea EnrollAcademicProcess + AcademicRecord y devuelve éxito" do
    res = nil
    assert_difference -> { EnrollAcademicProcess.count } => 1, -> { AcademicRecord.count } => 1 do
      res = reservar(section_id: @section.id)
    end
    assert_equal "success", res.estado
    assert_equal @section, res.section
  end

  test "sección llena devuelve error sin crear AcademicRecord" do
    llena = Section.create!(course: @course, code: "SLL", capacity: 1, modality: :nota_final, qualified: false)
    otro_u = User.create!(ci: "RX#{@uid}#{rand(10**6)}", email: "rx#{@uid}@test.com",
                          first_name: "Otro", last_name: "RC", password: "password123", updated_password: true)
    otro_g = Grade.create!(student: Student.create!(user: otro_u), study_plan: @plan, admission_type: @adm,
                           current_permanence_status: :regular)
    otro_e = EnrollAcademicProcess.create!(grade: otro_g, academic_process: @ap,
                                           enroll_status: :reservado, permanence_status: :regular)
    AcademicRecord.create!(section: llena, enroll_academic_process: otro_e, status: :sin_calificar)

    res = nil
    assert_no_difference -> { AcademicRecord.count } do
      res = reservar(section_id: llena.id)
    end
    assert_equal "error", res.estado
    assert_match(/cupos/i, res.mensaje)
  end

  test "liberar (section_id nil) elimina el AcademicRecord previo del curso" do
    reservar(section_id: @section.id)
    res = nil
    assert_difference -> { AcademicRecord.count } => -1 do
      res = reservar(section_id: nil)
    end
    assert_equal "success", res.estado
    assert_match(/liberado/i, res.mensaje)
  end

  test "sin cambios (liberar sin reserva previa) devuelve estado neutro, no nil" do
    res = reservar(section_id: nil)
    assert_not_nil res.estado
    assert_not_nil res.mensaje
  end
end
