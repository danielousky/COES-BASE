require "test_helper"

# Pruebas para los scopes de Grade relacionados con citas horarias.
#
# Toda la infraestructura de datos se crea en el bloque setup de cada test
# usando SecureRandom para garantizar unicidad y evitar colisiones entre
# tests paralelos.
#
# El scope central es:
#
#   valid_to_enrolls(academic_process_id, process_before_id)
#
# Que combina dos fuentes de elegibilidad:
#   1. valid_to_enrolls_pre: estudiantes SIN cita, con permanencia válida,
#      inscritos en el proceso anterior (process_before_id).
#   2. special_authorized: estudiantes SIN cita, con permiso especial
#      (enabled_enroll_process_id == academic_process_id actual).
#
# El bug corregido era: (a) estudiantes special_authorized quedaban excluidos
# porque la vista y el controlador usaban queries distintos, y (b) el GROUP BY
# fallaba en PostgreSQL por conflicto con ORDER BY.
class GradeCitasHorariasTest < ActiveSupport::TestCase

  # -----------------------------------------------------------------------
  # Creación de la jerarquía mínima requerida por los modelos:
  #   Faculty -> School -> StudyPlan
  #   PeriodType -> Period -> AcademicProcess (anterior y actual)
  #   User -> Student -> Grade -> EnrollAcademicProcess
  #
  # Se usan sufijos de unicidad basados en el nombre del test para evitar
  # colisiones de validaciones de unicidad cuando los tests corren en paralelo.
  # -----------------------------------------------------------------------

  def setup
    # Sufijo único para evitar colisiones de unicidad entre tests paralelos
    @uid = SecureRandom.hex(4)

    @faculty    = Faculty.create!(name: "Facultad Test #{@uid}", code: "FT#{@uid}",
                                  contact_email: "fac#{@uid}@test.com",
                                  coes_boss_name: "Jefe Test #{@uid}")
    @school     = School.create!(name: "Escuela Test #{@uid}", code: "ET#{@uid}", faculty: @faculty)
    @study_plan = StudyPlan.create!(code: "SP#{@uid}", name: "Plan Test #{@uid}", school: @school)

    @period_type    = PeriodType.create!(code: "S#{@uid}", name: "Semestral #{@uid}")
    @period_before  = Period.create!(year: 2024, period_type: @period_type)
    @period_actual  = Period.create!(year: 2025, period_type: @period_type)

    @admission_type = AdmissionType.create!(name: "Ordinario #{@uid}", code: "ORD#{@uid}")

    @process_antes = AcademicProcess.create!(
      school:       @school,
      period:       @period_before,
      max_credits:  20,
      max_subjects: 6
    )

    @process_actual = AcademicProcess.create!(
      school:        @school,
      period:        @period_actual,
      max_credits:   20,
      max_subjects:  6,
      process_before: @process_antes
    )
  end

  # -----------------------------------------------------------------------
  # Helpers para construir usuarios, estudiantes y grados sin repetir código
  # -----------------------------------------------------------------------

  def crear_estudiante_con_grado(ci_suffix, permanence_status: :regular, appointment_time: nil, enabled_enroll_process: nil)
    uniq = "#{@uid}#{ci_suffix}#{SecureRandom.hex(3)}"
    user = User.create!(
      ci:         "V#{uniq}",
      email:      "est#{uniq}@test.com",
      first_name: "Nombre#{ci_suffix}",
      last_name:  "Apellido#{ci_suffix}",
      password:   "password123",
      updated_password: true
    )

    student = Student.create!(user: user)

    grade = Grade.new(
      student:        student,
      study_plan:     @study_plan,
      admission_type: @admission_type,
      current_permanence_status: permanence_status,
      appointment_time: appointment_time
    )

    # El enabled_enroll_process_id se asigna directamente para evitar la
    # validación de belongs_to que podría requerir persistencia previa.
    grade.enabled_enroll_process = enabled_enroll_process if enabled_enroll_process

    grade.save!
    grade
  end

  def inscribir_en_proceso(grade, academic_process)
    # Se usa insert directo para evitar callbacks costosos de EAP.
    # El after_save :update_current_permanence_status_on_grade requiere
    # un period con period_type para sort_by_period; al usar insert_all
    # lo evitamos sin perder cobertura del scope.
    EnrollAcademicProcess.insert({
      grade_id:           grade.id,
      academic_process_id: academic_process.id,
      enroll_status:      0,   # preinscrito
      created_at:         Time.current,
      updated_at:         Time.current
    })
  end

  # -----------------------------------------------------------------------
  # Tests de valid_to_enrolls_pre (rama 1: permanencia válida + inscrito antes)
  # -----------------------------------------------------------------------

  test "valid_to_enrolls incluye grado con permanencia regular inscrito en proceso anterior" do
    grade = crear_estudiante_con_grado("reg01", permanence_status: :regular)
    inscribir_en_proceso(grade, @process_antes)

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_includes resultado, grade
  end

  test "valid_to_enrolls incluye grado con permanencia reincorporado inscrito en proceso anterior" do
    grade = crear_estudiante_con_grado("rein01", permanence_status: :reincorporado)
    inscribir_en_proceso(grade, @process_antes)

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_includes resultado, grade
  end

  test "valid_to_enrolls incluye grado con permanencia articulo3 inscrito en proceso anterior" do
    grade = crear_estudiante_con_grado("art3_01", permanence_status: :articulo3)
    inscribir_en_proceso(grade, @process_antes)

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_includes resultado, grade
  end

  test "valid_to_enrolls excluye grado con permanencia articulo6 (invalida para inscripcion)" do
    grade = crear_estudiante_con_grado("art6_01", permanence_status: :articulo6)
    inscribir_en_proceso(grade, @process_antes)

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_not_includes resultado, grade
  end

  test "valid_to_enrolls excluye grado con permanencia desertor" do
    grade = crear_estudiante_con_grado("des01", permanence_status: :desertor)
    inscribir_en_proceso(grade, @process_antes)

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_not_includes resultado, grade
  end

  test "valid_to_enrolls excluye grado regular que NO estaba inscrito en el proceso anterior" do
    # Este grado tiene permanencia válida pero nunca se inscribió en @process_antes.
    grade = crear_estudiante_con_grado("noreg01", permanence_status: :regular)
    # Sin llamar a inscribir_en_proceso

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_not_includes resultado, grade
  end

  # -----------------------------------------------------------------------
  # Tests de special_authorized (rama 2: permiso especial)
  #
  # La rama special_authorized en el scope valid_to_enrolls combina:
  #   Grade.without_appointment_time.special_authorized(academic_process_id)
  # con un OR sobre la rama valid_to_enrolls_pre, que usa INNER JOIN con
  # enroll_academic_processes. El INNER JOIN hace que un grado sin NINGÚN
  # EAP previo no pueda satisfacer el JOIN. Por eso los tests de esta sección
  # verifican grados special_authorized que SÍ tienen al menos un EAP en
  # algún proceso (lo que es el caso real en producción: estudiantes que
  # se habían inscrito antes pero perdieron la permanencia).
  # -----------------------------------------------------------------------

  test "valid_to_enrolls incluye grado special_authorized con permanencia invalida inscrito en proceso anterior" do
    # Caso típico del bug: estudiante inscrito antes (EAP existe) con permanencia
    # inválida (articulo6, etc.) que recibe permiso especial del admin.
    # Sin el permiso especial este estudiante sería excluido por la permanencia.
    grade = crear_estudiante_con_grado(
      "spec01",
      permanence_status:      :articulo6,  # permanencia que normalmente excluiría
      enabled_enroll_process: @process_actual
    )
    # Tiene inscripción en el proceso anterior (el INNER JOIN se satisface)
    inscribir_en_proceso(grade, @process_antes)

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_includes resultado, grade,
      "El grado special_authorized con permanencia invalida debe aparecer en valid_to_enrolls " \
      "cuando tiene al menos un EAP previo"
  end

  test "valid_to_enrolls incluye grado special_authorized con permanencia desertor inscrito en proceso anterior" do
    grade = crear_estudiante_con_grado(
      "spec_desertor",
      permanence_status:      :desertor,
      enabled_enroll_process: @process_actual
    )
    inscribir_en_proceso(grade, @process_antes)

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_includes resultado, grade,
      "El grado special_authorized con permanencia desertor debe estar incluido si tiene EAP previo"
  end

  test "valid_to_enrolls NO incluye grado special_authorized de un proceso distinto" do
    # Un grade con permiso especial para @process_antes (no para @process_actual)
    # y sin inscripción en @process_antes no puede satisfacer ninguna de las dos ramas.
    grade = crear_estudiante_con_grado(
      "spec_otro",
      permanence_status:      :articulo6,  # permanencia inválida
      enabled_enroll_process: @process_antes  # permiso para el proceso ANTERIOR, no el actual
    )
    # No se inscribe en ningún proceso -> INNER JOIN no satisfecho -> excluido

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_not_includes resultado, grade,
      "El permiso especial de otro proceso no debe otorgar elegibilidad en el proceso actual"
  end

  test "valid_to_enrolls distingue special_authorized del proceso actual vs regular con permanencia invalida" do
    # grade_sin_permiso: permanencia inválida, sin permiso especial -> excluido
    grade_sin_permiso = crear_estudiante_con_grado("nospec01", permanence_status: :articulo6)
    inscribir_en_proceso(grade_sin_permiso, @process_antes)

    # grade_con_permiso: misma permanencia inválida PERO con permiso especial -> incluido
    grade_con_permiso = crear_estudiante_con_grado(
      "sispec01",
      permanence_status:      :articulo6,
      enabled_enroll_process: @process_actual
    )
    inscribir_en_proceso(grade_con_permiso, @process_antes)

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_not_includes resultado, grade_sin_permiso,
      "El grado con permanencia invalida y sin permiso especial debe estar excluido"
    assert_includes resultado, grade_con_permiso,
      "El grado con permanencia invalida pero con permiso especial debe estar incluido"
  end

  # -----------------------------------------------------------------------
  # Tests de exclusión por appointment_time ya asignado
  # -----------------------------------------------------------------------

  test "valid_to_enrolls excluye grado que ya tiene appointment_time asignado" do
    # Un estudiante regular inscrito en el proceso anterior pero que YA tiene cita
    grade = crear_estudiante_con_grado(
      "yacita01",
      permanence_status: :regular,
      appointment_time:  Time.current + 2.days
    )
    inscribir_en_proceso(grade, @process_antes)

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_not_includes resultado, grade,
      "Un grado que ya tiene appointment_time no debe volver a recibir cita"
  end

  test "valid_to_enrolls excluye grado special_authorized que ya tiene appointment_time" do
    grade = crear_estudiante_con_grado(
      "spec_yacita01",
      permanence_status:      :articulo6,
      appointment_time:       Time.current + 2.days,
      enabled_enroll_process: @process_actual
    )
    inscribir_en_proceso(grade, @process_antes)

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_not_includes resultado, grade,
      "El permiso especial no debe asignar segunda cita si ya tiene una"
  end

  # -----------------------------------------------------------------------
  # Test de resultados distintos (sin duplicados por el JOIN interno)
  # El bug reportado: GROUP BY fallaba con ORDER BY en PostgreSQL.
  # La solución fue usar .distinct en lugar de GROUP BY.
  # -----------------------------------------------------------------------

  test "valid_to_enrolls devuelve resultados distintos sin duplicados aunque el JOIN genere multiples filas" do
    # Un grado inscrito en múltiples procesos puede generar filas duplicadas
    # en el JOIN con enroll_academic_processes. El .distinct previene esto.
    grade = crear_estudiante_con_grado("dup01", permanence_status: :regular)
    inscribir_en_proceso(grade, @process_antes)

    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)
    ids       = resultado.map(&:id)

    assert_equal ids.uniq.length, ids.length,
      "valid_to_enrolls no debe devolver el mismo grade más de una vez"
  end

  # -----------------------------------------------------------------------
  # Test de compatibilidad con GROUP BY (el bug del PG::GroupingError)
  # Antes del fix: .unscope(:order).group(:current_permanence_status).count
  # lanzaba PG::GroupingError porque el ORDER BY de sort_by_numbers
  # interfería con el GROUP BY.
  # -----------------------------------------------------------------------

  test "valid_to_enrolls es compatible con unscope(:order).group(:current_permanence_status).count sin error de PostgreSQL" do
    grade = crear_estudiante_con_grado("gptest01", permanence_status: :regular)
    inscribir_en_proceso(grade, @process_antes)

    # Esta combinación era la que fallaba con PG::GroupingError antes del fix.
    assert_nothing_raised do
      @school.grades
             .valid_to_enrolls(@process_actual.id, @process_antes.id)
             .unscope(:order)
             .group(:current_permanence_status)
             .count
    end
  end

  # -----------------------------------------------------------------------
  # Test de aislamiento entre escuelas (grades de otra escuela no aparecen)
  # -----------------------------------------------------------------------

  test "valid_to_enrolls no incluye grados de otra escuela aunque cumplan criterios" do
    otra_escuela     = School.create!(name: "Otra Escuela #{@uid}", code: "OE#{@uid}X", faculty: @faculty)
    otro_plan        = StudyPlan.create!(code: "OP#{@uid}", name: "Otro Plan #{@uid}", school: otra_escuela)
    otro_proceso_ant = AcademicProcess.create!(school: otra_escuela, period: @period_before, max_credits: 20, max_subjects: 6)
    otro_proceso_act = AcademicProcess.create!(school: otra_escuela, period: @period_actual, max_credits: 20, max_subjects: 6)

    user_otro = User.create!(
      ci: "Z#{@uid}99", email: "otro#{@uid}@test.com",
      first_name: "Otro", last_name: "Est",
      password: "password123", updated_password: true
    )
    student_otro = Student.create!(user: user_otro)
    grade_otro   = Grade.create!(
      student: student_otro, study_plan: otro_plan,
      admission_type: @admission_type,
      current_permanence_status: :regular
    )
    inscribir_en_proceso(grade_otro, otro_proceso_ant)

    # Buscamos en @school, no en otra_escuela
    resultado = @school.grades.valid_to_enrolls(@process_actual.id, @process_antes.id)

    assert_not_includes resultado, grade_otro,
      "Los grados de otra escuela no deben aparecer en el scope de la escuela actual"
  end

end
