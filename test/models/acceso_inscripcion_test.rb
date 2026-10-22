require "test_helper"

# AccesoInscripcion: las condiciones de la pantalla del estudiante para inscribirse por su cuenta.
class AccesoInscripcionTest < ActiveSupport::TestCase
  setup do
    @uid = SecureRandom.hex(4)
    faculty = Faculty.create!(name: "Fac AI #{@uid}", code: "FAI#{@uid}", contact_email: "fai#{@uid}@test.com", coes_boss_name: "Jefe #{@uid}")
    school = School.create!(name: "Esc AI #{@uid}", code: "EAI#{@uid}", faculty: faculty)
    plan = StudyPlan.create!(code: "SPAI#{@uid}", name: "Plan AI #{@uid}", school: school, modality: :Semestral)
    tipo = PeriodType.create!(code: "A#{@uid}", name: "Período #{@uid}")
    @anterior = AcademicProcess.create!(school: school, period: Period.create!(year: 2024, period_type: tipo), modality: :Semestral,
                                        max_credits: 24, max_subjects: 6)
    @proceso = AcademicProcess.create!(school: school, period: Period.create!(year: 2025, period_type: tipo), modality: :Semestral,
                                       max_credits: 24, max_subjects: 6, process_before: @anterior, enroll: true)
    user = User.create!(ci: "#{rand(10**8)}", email: "ai#{@uid}@test.com", first_name: 'Ana', last_name: 'Acceso',
                        password: 'password123', updated_password: true)
    @grade = Grade.create!(student: Student.create!(user: user), study_plan: plan,
                           admission_type: AdmissionType.create!(name: "Adm #{@uid}", code: "AAI#{@uid}"))
  end

  def inscribir_en(proceso, permanencia: :regular, estado: :confirmado)
    EnrollAcademicProcess.create!(grade: @grade, academic_process: proceso, enroll_status: estado, permanence_status: permanencia)
  end

  def acceso
    AccesoInscripcion.new(@grade.reload, @proceso.reload)
  end

  test "regular inscrito en el anterior y sin cita horaria: puede inscribirse" do
    inscribir_en(@anterior)
    assert_equal :directa, acceso.estado
    assert acceso.habilitado?
  end

  test "período cerrado o de otra modalidad" do
    @proceso.update!(enroll: false)
    assert_equal :proceso_cerrado, acceso.estado

    @proceso.update!(enroll: true, modality: :Anual)
    assert_equal :proceso_cerrado, acceso.estado
  end

  test "ya preinscrito o confirmado: no vuelve a inscribirse; reservado sí continúa" do
    inscribir_en(@anterior)
    inscripcion = inscribir_en(@proceso, estado: :preinscrito)
    assert_equal :ya_inscrito, acceso.estado

    inscripcion.update!(enroll_status: :reservado)
    assert_equal :directa, acceso.estado
  end

  test "con cita horaria: según la hora de su cita" do
    inscribir_en(@anterior)
    EnrollmentDay.new(academic_process: @proceso, start: 2.days.ago, total_duration_hours: 1).save(validate: false)
    assert_equal :sin_cita, acceso.estado

    @grade.update_columns(appointment_time: 10.minutes.ago, duration_slot_time: 30)
    assert_equal :es_su_hora, acceso.estado

    @grade.update_columns(appointment_time: 1.day.from_now)
    assert_equal :cita_futura, acceso.estado

    @grade.update_columns(appointment_time: 1.day.ago)
    assert_equal :cita_vencida, acceso.estado
    assert_not acceso.habilitado?
  end

  test "estados de permanencia que impiden inscribirse por su cuenta" do
    inscribir_en(@anterior)
    {articulo6: :reglamento, egresado: :por_control_estudio, desertor: :permanencia_impide}.each do |permanencia, estado|
      @grade.update_columns(current_permanence_status: Grade.current_permanence_statuses[permanencia])
      assert_equal estado, acceso.estado, permanencia
    end
  end

  test "un nuevo puede inscribirse; un regular sin inscripción en el período anterior, no" do
    assert_equal :directa, acceso.estado

    viejo = AcademicProcess.create!(school: @proceso.school, period: Period.create!(year: 2023, period_type: @proceso.period.period_type),
                                    modality: :Semestral, max_credits: 24, max_subjects: 6)
    inscribir_en(viejo)
    @grade.update_columns(current_permanence_status: Grade.current_permanence_statuses[:regular])
    assert_equal :no_inscrito_anterior, acceso.estado
    assert_match(/período anterior/, acceso.mensaje)
  end
end
