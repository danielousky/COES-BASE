require "test_helper"

# Pruebas de atomicidad ACID para AcademicRecordsController#create
# (app/controllers/academic_records_controller.rb:46).
#
# La acción crea Curso + Sección + Histórico Académico (+ Calificación
# opcional) dentro de un bloque ActiveRecord::Base.transaction. Si cualquier
# paso falla, ningún registro queda persistido.
#
# Estos tests respaldan la afirmación del informe de auditoría sobre
# transacciones ACID en el módulo de carga de históricos académicos
# (mayo 2026).
class AcademicRecordsCreateAcidTest < ActionDispatch::IntegrationTest
  # Ver explicación en reserve_space_acid_test.rb. Vaciamos la lista de
  # fixtures sólo para esta clase (las transacciones de aislamiento se
  # mantienen).
  self.fixture_table_names = []

  setup do
    @uid       = SecureRandom.hex(4)
    @uid_alpha = (("a".."z").to_a.sample(8)).join

    # Jerarquía
    @faculty = Faculty.create!(
      name:           "Facultad AR #{@uid}",
      code:           "FAR#{@uid}",
      contact_email:  "far#{@uid}@test.com",
      coes_boss_name: "Jefe AR #{@uid}"
    )
    @school = School.create!(name: "Escuela AR #{@uid}", code: "EAR#{@uid}", faculty: @faculty)
    @study_plan = StudyPlan.create!(code: "SPAR#{@uid}", name: "Plan AR #{@uid}", school: @school)
    @admission_type = AdmissionType.create!(name: "Adm AR #{@uid}", code: "AAR#{@uid}")

    @period_type = PeriodType.create!(code: "U#{@uid}", name: "Único #{@uid}")
    @period      = Period.create!(year: 2025, period_type: @period_type)

    @academic_process = AcademicProcess.create!(
      school: @school, period: @period,
      max_credits: 24, max_subjects: 6
    )

    # Asignatura numérica para que se evalúe la rama de qualifications
    @subject_type = SubjectType.create!(code: "OB#{@uid_alpha}", name: "Oblig AR #{@uid}")
    @area         = Area.create!(name: "Area AR #{@uid}", school: @school)
    @departament  = Departament.create!(name: "Dpto AR #{@uid}", school: @school)
    @departament.areas << @area
    @subject = Subject.create!(
      code:               "MAT#{@uid}",
      name:               "Matemática AR #{@uid}",
      ordinal:            1,
      subject_type:       @subject_type,
      qualification_type: :numerica,
      unit_credits:       4,
      area:               @area,
      departament:        @departament,
      school:             @school
    )

    # Estudiante + Grade + EAP (preexistente; create solo agrega histórico)
    @user = User.create!(
      ci:               "AR#{@uid}#{rand(10**6)}",
      email:            "ar#{@uid}@test.com",
      first_name:       "Histo",
      last_name:        "Rico",
      password:         "password123",
      updated_password: true
    )
    @student = Student.create!(user: @user)
    @grade   = Grade.create!(
      student: @student, study_plan: @study_plan, admission_type: @admission_type,
      current_permanence_status: :regular
    )
    @eap = EnrollAcademicProcess.create!(
      grade: @grade, academic_process: @academic_process,
      enroll_status: :preinscrito, permanence_status: :regular
    )

    sign_in @user
  end

  # ---------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------

  test "happy path: crea Course + Section + AcademicRecord + Qualification" do
    assert_difference -> { Course.count }         => 1,
                      -> { Section.count }        => 1,
                      -> { AcademicRecord.count } => 1,
                      -> { Qualification.count }  => 1 do
      post academic_records_path, params: post_params(qualification_value: 18)
    end

    course  = Course.find_by(subject: @subject, academic_process: @academic_process)
    section = course.sections.find_by(code: "Z9")
    ar      = AcademicRecord.find_by(section: section, enroll_academic_process: @eap)
    qa      = ar.qualifications.find_by(type_q: :final)

    assert_not_nil course
    assert_not_nil section
    assert_not_nil ar
    assert_not_nil qa
    assert_equal 18, qa.value
  end

  # ---------------------------------------------------------------------
  # Rollback: la calificación inválida revierte Course + Section + AR
  # ---------------------------------------------------------------------

  test "rollback: qualification value inválido revierte Course/Section/AcademicRecord" do
    # value = 99 falla la validación numericality in: 0..20 -> qa.save! lanza
    # ActiveRecord::RecordInvalid DENTRO de la transacción -> todo se revierte.
    assert_no_difference [-> { Course.count }, -> { Section.count },
                          -> { AcademicRecord.count }, -> { Qualification.count }] do
      post academic_records_path, params: post_params(qualification_value: 99)
    end

    assert_nil Course.find_by(subject: @subject, academic_process: @academic_process),
      "Course recién creado NO debe persistir cuando la qualification posterior falla " \
      "(atomicidad de la transacción)"
  end

  # ---------------------------------------------------------------------
  # Rollback: section.save! falla por code demasiado largo
  # ---------------------------------------------------------------------

  test "rollback: section_code mayor a 7 caracteres revierte la creación del Course" do
    # Section valida length(code) in 1..7 -> section.save! falla -> rollback.
    assert_no_difference [-> { Course.count }, -> { Section.count },
                          -> { AcademicRecord.count }] do
      post academic_records_path, params: post_params(section_code: "DEMASIADOLARGO")
    end

    assert_nil Course.find_by(subject: @subject, academic_process: @academic_process),
      "Course creado por find_or_create_by! debe revertirse cuando section.save! falla"
  end

  private

  def post_params(qualification_value: nil, section_code: "Z9")
    params = {
      academic_record: {
        section_id:                 0, # se sobreescribe en el controller
        enroll_academic_process_id: @eap.id,
        status:                     "sin_calificar"
      },
      course:       { subject_id: @subject.id },
      section_type: "nota_final",
      section_code: section_code
    }
    if qualification_value
      params[:qualifications] = { type_q: "final", value: qualification_value.to_s }
    end
    params
  end
end
