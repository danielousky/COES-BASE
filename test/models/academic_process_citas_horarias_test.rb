require "test_helper"

# Pruebas para los métodos de AcademicProcess relacionados con la asignación
# de citas horarias a estudiantes:
#
#   - grades_ready_to_enrollment_day: devuelve grados elegibles ordenados por
#     sus propios índices de rendimiento (efficiency, simple_average, weighted_average).
#
#   - enrolleds_ready_to_enrollment_day: devuelve los mismos grados elegibles
#     pero ordenados por los índices de rendimiento del PROCESO ANTERIOR (EAP).
#     También incluye grados special_authorized que pueden no tener EAP.
#
#   - update_grades_enrollment_day: asigna appointment_time y duration_slot_time
#     a un lote de grados, devolviendo el total actualizado.
#
# Estos métodos son los que el controlador EnrollmentDaysController#create
# invoca en el loop de distribución de franjas horarias.
class AcademicProcessCitasHorariasTest < ActiveSupport::TestCase

  # -----------------------------------------------------------------------
  # Setup: misma jerarquía que en GradeCitasHorariasTest pero orientada
  # a probar los métodos de AcademicProcess.
  # -----------------------------------------------------------------------

  def setup
    @uid = SecureRandom.hex(4)

    @faculty    = Faculty.create!(name: "Facultad AP #{@uid}", code: "FA#{@uid}",
                                  contact_email: "fap#{@uid}@test.com",
                                  coes_boss_name: "Jefe AP #{@uid}")
    @school     = School.create!(name: "Escuela AP #{@uid}", code: "EA#{@uid}", faculty: @faculty)
    @study_plan = StudyPlan.create!(code: "SPAP#{@uid}", name: "Plan AP #{@uid}", school: @school)

    @period_type   = PeriodType.create!(code: "T#{@uid}", name: "Trimestral #{@uid}")
    @period_antes  = Period.create!(year: 2024, period_type: @period_type)
    @period_actual = Period.create!(year: 2025, period_type: @period_type)

    @admission_type = AdmissionType.create!(name: "Admin AP #{@uid}", code: "AAP#{@uid}")

    @process_antes = AcademicProcess.create!(
      school:       @school,
      period:       @period_antes,
      max_credits:  20,
      max_subjects: 6
    )

    @process_actual = AcademicProcess.create!(
      school:         @school,
      period:         @period_actual,
      max_credits:    20,
      max_subjects:   6,
      process_before: @process_antes
    )
  end

  # -----------------------------------------------------------------------
  # Helpers
  # -----------------------------------------------------------------------

  def crear_grado(ci_suffix, permanence_status: :regular, efficiency: 1.0,
                  simple_average: 0.0, weighted_average: 0.0,
                  appointment_time: nil, enabled_enroll_process: nil)
    uniq = "#{@uid}#{ci_suffix}#{SecureRandom.hex(3)}"
    user = User.create!(
      ci:               "G#{uniq}",
      email:            "grd#{uniq}@test.com",
      first_name:       "N#{ci_suffix}",
      last_name:        "A#{ci_suffix}",
      password:         "password123",
      updated_password: true
    )
    student = Student.create!(user: user)
    grade   = Grade.new(
      student:                   student,
      study_plan:                @study_plan,
      admission_type:            @admission_type,
      current_permanence_status: permanence_status,
      efficiency:                efficiency,
      simple_average:            simple_average,
      weighted_average:          weighted_average,
      appointment_time:          appointment_time
    )
    grade.enabled_enroll_process = enabled_enroll_process if enabled_enroll_process
    grade.save!
    grade
  end

  def inscribir(grade, academic_process, efficiency: 1.0, simple_average: 0.0, weighted_average: 0.0)
    EnrollAcademicProcess.insert({
      grade_id:            grade.id,
      academic_process_id: academic_process.id,
      enroll_status:       0,
      efficiency:          efficiency,
      simple_average:      simple_average,
      weighted_average:    weighted_average,
      created_at:          Time.current,
      updated_at:          Time.current
    })
  end

  # -----------------------------------------------------------------------
  # grades_ready_to_enrollment_day
  # -----------------------------------------------------------------------

  test "grades_ready_to_enrollment_day devuelve nil cuando no hay process_before" do
    proceso_sin_antes = AcademicProcess.create!(
      school: @school, period: Period.create!(year: 2023, period_type: @period_type),
      max_credits: 20, max_subjects: 6
      # sin process_before
    )

    assert_nil proceso_sin_antes.grades_ready_to_enrollment_day
  end

  test "grades_ready_to_enrollment_day incluye grado regular inscrito en proceso anterior" do
    grade = crear_grado("rg01", permanence_status: :regular)
    inscribir(grade, @process_antes)

    resultado = @process_actual.grades_ready_to_enrollment_day

    assert_includes resultado, grade
  end

  test "grades_ready_to_enrollment_day excluye grado que ya tiene cita horaria" do
    grade = crear_grado("rg_cita01", permanence_status: :regular,
                         appointment_time: Time.current + 1.day)
    inscribir(grade, @process_antes)

    resultado = @process_actual.grades_ready_to_enrollment_day

    assert_not_includes resultado, grade
  end

  test "grades_ready_to_enrollment_day ordena por efficiency descendente" do
    grade_alta  = crear_grado("eff_hi", permanence_status: :regular, efficiency: 0.9)
    grade_media = crear_grado("eff_md", permanence_status: :regular, efficiency: 0.5)
    grade_baja  = crear_grado("eff_lo", permanence_status: :regular, efficiency: 0.1)

    [grade_alta, grade_media, grade_baja].each { |g| inscribir(g, @process_antes) }

    resultado = @process_actual.grades_ready_to_enrollment_day

    # Verificamos que grade_alta aparece antes que grade_baja en la lista
    idx_alta = resultado.index(grade_alta)
    idx_baja = resultado.index(grade_baja)

    assert idx_alta < idx_baja,
      "El grado con mayor efficiency debe aparecer antes en grades_ready_to_enrollment_day"
  end

  test "grades_ready_to_enrollment_day incluye grado special_authorized sin inscripcion anterior" do
    grade_especial = crear_grado(
      "spec_rdy01",
      permanence_status:      :nuevo,
      enabled_enroll_process: @process_actual
    )
    # Sin inscribir en @process_antes

    resultado = @process_actual.grades_ready_to_enrollment_day

    assert_includes resultado, grade_especial,
      "grades_ready_to_enrollment_day debe incluir grados special_authorized"
  end

  # -----------------------------------------------------------------------
  # enrolleds_ready_to_enrollment_day
  # -----------------------------------------------------------------------

  test "enrolleds_ready_to_enrollment_day devuelve nil cuando no hay process_before" do
    proceso_sin_antes = AcademicProcess.create!(
      school: @school, period: Period.create!(year: 2022, period_type: @period_type),
      max_credits: 20, max_subjects: 6
    )

    assert_nil proceso_sin_antes.enrolleds_ready_to_enrollment_day
  end

  test "enrolleds_ready_to_enrollment_day incluye los mismos grados que grades_ready_to_enrollment_day" do
    grade1 = crear_grado("e01", permanence_status: :regular)
    grade2 = crear_grado("e02", permanence_status: :reincorporado)
    [grade1, grade2].each { |g| inscribir(g, @process_antes) }

    por_numeros_propios   = @process_actual.grades_ready_to_enrollment_day.to_a
    por_numeros_anteriores = @process_actual.enrolleds_ready_to_enrollment_day

    assert_equal por_numeros_propios.sort_by(&:id),
                 por_numeros_anteriores.sort_by(&:id),
      "Ambos métodos deben operar sobre el mismo conjunto de grados elegibles"
  end

  test "enrolleds_ready_to_enrollment_day ordena por efficiency del proceso anterior" do
    grade_eff_alta = crear_grado("enr_hi", permanence_status: :regular)
    grade_eff_baja = crear_grado("enr_lo", permanence_status: :regular)

    inscribir(grade_eff_alta, @process_antes, efficiency: 0.9)
    inscribir(grade_eff_baja, @process_antes, efficiency: 0.2)

    resultado = @process_actual.enrolleds_ready_to_enrollment_day

    idx_alta = resultado.index(grade_eff_alta)
    idx_baja = resultado.index(grade_eff_baja)

    assert idx_alta < idx_baja,
      "El grado con mayor efficiency en el proceso anterior debe aparecer primero"
  end

  test "enrolleds_ready_to_enrollment_day incluye grado special_authorized sin EAP en proceso anterior" do
    # Este es el caso del bug: el grado special_authorized no tiene EAP en
    # el proceso anterior, por lo que eap_numbers.fetch devuelve [0,0,0]
    # y el grado queda al final del orden pero SÍ está incluido.
    grade_especial = crear_grado(
      "spec_enr01",
      permanence_status:      :nuevo,
      enabled_enroll_process: @process_actual
    )
    # Sin inscribir en @process_antes

    resultado = @process_actual.enrolleds_ready_to_enrollment_day

    assert_includes resultado, grade_especial,
      "enrolleds_ready_to_enrollment_day debe incluir grados special_authorized " \
      "aunque no tengan EAP en el proceso anterior"
  end

  test "enrolleds_ready_to_enrollment_day pone special_authorized al final cuando no tiene EAP previo" do
    # Grado regular con buenos números -> va primero
    grade_regular  = crear_grado("enr_reg", permanence_status: :regular)
    grade_especial = crear_grado("enr_spec", permanence_status: :nuevo,
                                  enabled_enroll_process: @process_actual)

    inscribir(grade_regular, @process_antes, efficiency: 0.8, simple_average: 16.0, weighted_average: 15.0)
    # grade_especial sin EAP -> eap_numbers.fetch devuelve [0,0,0] -> al final

    resultado = @process_actual.enrolleds_ready_to_enrollment_day

    idx_regular  = resultado.index(grade_regular)
    idx_especial = resultado.index(grade_especial)

    assert idx_regular < idx_especial,
      "El grado regular con buenos números debe preceder al special_authorized sin EAP"
  end

  test "enrolleds_ready_to_enrollment_day devuelve Array (resultado de sort_by)" do
    grade = crear_grado("arr01", permanence_status: :regular)
    inscribir(grade, @process_antes)

    resultado = @process_actual.enrolleds_ready_to_enrollment_day

    assert_kind_of Array, resultado
  end

  # -----------------------------------------------------------------------
  # update_grades_enrollment_day
  # -----------------------------------------------------------------------

  test "update_grades_enrollment_day asigna appointment_time a los grados del lote" do
    grade1 = crear_grado("upd01", permanence_status: :regular)
    grade2 = crear_grado("upd02", permanence_status: :regular)
    [grade1, grade2].each { |g| inscribir(g, @process_antes) }

    hora_cita = Time.current + 3.days

    # final_lap = 1 (índice) -> cubre grade1 y grade2 (índices 0 y 1)
    @process_actual.update_grades_enrollment_day(false, 1, hora_cita, 30)

    grade1.reload
    grade2.reload

    assert_equal hora_cita.to_i, grade1.appointment_time.to_i,
      "grade1 debe tener el appointment_time asignado"
    assert_equal hora_cita.to_i, grade2.appointment_time.to_i,
      "grade2 debe tener el appointment_time asignado"
  end

  test "update_grades_enrollment_day asigna duration_slot_time correctamente" do
    grade = crear_grado("dur01", permanence_status: :regular)
    inscribir(grade, @process_antes)

    hora_cita      = Time.current + 4.days
    duracion_franja = 45

    @process_actual.update_grades_enrollment_day(false, 0, hora_cita, duracion_franja)

    grade.reload

    assert_equal duracion_franja, grade.duration_slot_time
  end

  test "update_grades_enrollment_day retorna el numero de grados actualizados" do
    grade1 = crear_grado("cnt01", permanence_status: :regular)
    grade2 = crear_grado("cnt02", permanence_status: :regular)
    grade3 = crear_grado("cnt03", permanence_status: :regular)
    [grade1, grade2, grade3].each { |g| inscribir(g, @process_antes) }

    hora_cita = Time.current + 5.days

    # final_lap = 1 -> cubre grados en índices 0 y 1 = 2 grados
    total = @process_actual.update_grades_enrollment_day(false, 1, hora_cita, 30)

    assert_equal 2, total,
      "update_grades_enrollment_day debe retornar 2 cuando final_lap es 1"
  end

  test "update_grades_enrollment_day retorna 0 cuando no hay grados elegibles" do
    # No se crea ningún grado elegible
    hora_cita = Time.current + 6.days
    total     = @process_actual.update_grades_enrollment_day(false, 0, hora_cita, 30)

    assert_equal 0, total,
      "update_grades_enrollment_day debe retornar 0 si no hay grados elegibles"
  end

  test "update_grades_enrollment_day con by_before_process true usa enrolleds_ready_to_enrollment_day" do
    grade = crear_grado("byproc01", permanence_status: :regular)
    inscribir(grade, @process_antes, efficiency: 0.75)

    hora_cita = Time.current + 7.days

    # by_before_process = true -> usa enrolleds_ready_to_enrollment_day (ordenado por EAP anterior)
    total = @process_actual.update_grades_enrollment_day(true, 0, hora_cita, 30)

    assert_equal 1, total
    grade.reload
    assert_equal hora_cita.to_i, grade.appointment_time.to_i
  end

  test "update_grades_enrollment_day no reasigna grados que ya tienen cita horaria" do
    # Grado ya con cita -> no debe estar en valid_to_enrolls -> no se modifica
    hora_original = Time.current + 1.day
    grade_con_cita = crear_grado("nocambio01", permanence_status: :regular,
                                   appointment_time: hora_original)
    inscribir(grade_con_cita, @process_antes)

    hora_nueva = Time.current + 8.days
    @process_actual.update_grades_enrollment_day(false, 0, hora_nueva, 30)

    grade_con_cita.reload

    assert_equal hora_original.to_i, grade_con_cita.appointment_time.to_i,
      "Un grado que ya tiene cita horaria no debe ser modificado"
  end

end
