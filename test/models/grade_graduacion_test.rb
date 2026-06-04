require "test_helper"

# Pruebas del módulo Proceso Graduación en Grade.
#
# Flujo (verificado contra COES v1): Tesista → Posible Graduando → Graduando → Graduado.
# "Tesista" es DERIVADO: un Grade cursante (o legacy :tesista) con una asignatura de
# tesis (SubjectType.code 'P') inscrita en un proceso académico activo, no retirada.
#
# Cubre:
#   - promover_graduacion! / revertir_graduacion! (transiciones válidas e inválidas)
#   - sync graduado ↔ egresado
#   - scope :tesistas (derivación correcta) y :of_schools
#   - tesis_activa
#
# Toda la jerarquía se crea inline con sufijo único (SecureRandom) para no
# colisionar con los tests paralelos, igual que grade_citas_horarias_test.rb.
class GradeGraduacionTest < ActiveSupport::TestCase
  def setup
    @uid       = SecureRandom.hex(4)
    @uid_alpha = (("a".."z").to_a.sample(8)).join

    @faculty    = Faculty.create!(name: "Fac Grad #{@uid}", code: "FG#{@uid}",
                                  contact_email: "fg#{@uid}@test.com", coes_boss_name: "Jefe #{@uid}")
    @school     = School.create!(name: "Esc Grad #{@uid}", code: "EG#{@uid}", faculty: @faculty)
    @study_plan = StudyPlan.create!(code: "SPG#{@uid}", name: "Plan Grad #{@uid}", school: @school)
    @admission_type = AdmissionType.create!(name: "Adm #{@uid}", code: "ADG#{@uid}")

    @period_type = PeriodType.create!(code: "U#{@uid}", name: "Único #{@uid}")
    @period      = Period.create!(year: 2025, period_type: @period_type)

    @proceso_activo = AcademicProcess.create!(school: @school, period: @period,
                                              max_credits: 24, max_subjects: 6, active: true)
  end

  # --- helpers de construcción -------------------------------------------

  def crear_grade(graduate_status: :cursante, permanence: :regular, school: @school, plan: @study_plan)
    user = User.create!(ci: "G#{@uid}#{rand(10**8)}", email: "g#{@uid}#{rand(10**6)}@test.com",
                        first_name: "Est", last_name: "Udiante", password: "password123", updated_password: true)
    student = Student.create!(user: user)
    Grade.create!(student: student, study_plan: plan, admission_type: @admission_type,
                  graduate_status: graduate_status, current_permanence_status: permanence)
  end

  # Inscribe una tesis (asignatura code 'P') al grade en un proceso académico dado.
  def inscribir_tesis(grade, proceso: @proceso_activo, status: :sin_calificar)
    thesis_type = SubjectType.find_or_create_by!(code: Grade::THESIS_SUBJECT_TYPE_CODE) { |st| st.name = "PROYECTO #{@uid}" }
    area        = Area.create!(name: "Area #{@uid}#{rand(10**4)}", school: @school)
    departament = Departament.create!(name: "Dpto #{@uid}#{rand(10**4)}", school: @school)
    departament.areas << area
    subject = Subject.create!(code: "TES#{@uid}#{rand(10**4)}", name: "Tesis #{@uid}", ordinal: 10,
                              subject_type: thesis_type, qualification_type: :absoluta, unit_credits: 8,
                              area: area, departament: departament, school: @school)
    course  = Course.create!(subject: subject, academic_process: proceso)
    section = Section.create!(course: course, code: "T#{rand(10**5)}", capacity: 30, modality: :nota_final, qualified: false)
    eap     = EnrollAcademicProcess.create!(grade: grade, academic_process: proceso,
                                            enroll_status: :preinscrito, permanence_status: :regular)
    AcademicRecord.create!(section: section, enroll_academic_process: eap, status: status)
  end

  # ======================================================================
  # TRANSICIONES
  # ======================================================================

  test "promover cursante → posible_graduando" do
    g = crear_grade(graduate_status: :cursante)
    g.promover_graduacion!(:posible_graduando)
    assert_equal "posible_graduando", g.reload.graduate_status
  end

  test "promover legacy :tesista → posible_graduando" do
    g = crear_grade(graduate_status: :tesista)
    g.promover_graduacion!(:posible_graduando)
    assert_equal "posible_graduando", g.reload.graduate_status
  end

  test "promover posible_graduando → graduando" do
    g = crear_grade(graduate_status: :posible_graduando)
    g.promover_graduacion!(:graduando)
    assert_equal "graduando", g.reload.graduate_status
  end

  test "promover graduando → graduado setea permanencia egresado" do
    g = crear_grade(graduate_status: :graduando, permanence: :regular)
    g.promover_graduacion!(:graduado)
    g.reload
    assert_equal "graduado", g.graduate_status
    assert_equal "egresado", g.current_permanence_status
  end

  test "promover a graduado NO pisa egresado_doble_titulo" do
    g = crear_grade(graduate_status: :graduando, permanence: :egresado_doble_titulo)
    g.promover_graduacion!(:graduado)
    assert_equal "egresado_doble_titulo", g.reload.current_permanence_status
  end

  test "transición no permitida lanza TransicionGraduacionInvalida" do
    g = crear_grade(graduate_status: :cursante)
    assert_raises(Grade::TransicionGraduacionInvalida) { g.promover_graduacion!(:graduando) }
    assert_equal "cursante", g.reload.graduate_status
  end

  test "estado destino inválido lanza TransicionGraduacionInvalida" do
    g = crear_grade(graduate_status: :cursante)
    assert_raises(Grade::TransicionGraduacionInvalida) { g.promover_graduacion!(:postgrado) }
  end

  # ======================================================================
  # REVERSIONES
  # ======================================================================

  test "revertir graduado → graduando restaura permanencia a regular" do
    g = crear_grade(graduate_status: :graduado, permanence: :egresado)
    g.revertir_graduacion!
    g.reload
    assert_equal "graduando", g.graduate_status
    assert_equal "regular", g.current_permanence_status
  end

  test "revertir graduando → posible_graduando" do
    g = crear_grade(graduate_status: :graduando)
    g.revertir_graduacion!
    assert_equal "posible_graduando", g.reload.graduate_status
  end

  test "revertir posible_graduando → cursante" do
    g = crear_grade(graduate_status: :posible_graduando)
    g.revertir_graduacion!
    assert_equal "cursante", g.reload.graduate_status
  end

  test "no se puede revertir desde cursante" do
    g = crear_grade(graduate_status: :cursante)
    assert_raises(Grade::TransicionGraduacionInvalida) { g.revertir_graduacion! }
  end

  # ======================================================================
  # SCOPE :tesistas  y  tesis_activa
  # ======================================================================

  test "tesistas incluye cursante con tesis sin calificar en proceso activo" do
    g = crear_grade(graduate_status: :cursante)
    inscribir_tesis(g)
    assert_includes Grade.tesistas, g
  end

  test "tesistas incluye legacy :tesista con tesis activa" do
    g = crear_grade(graduate_status: :tesista)
    inscribir_tesis(g)
    assert_includes Grade.tesistas, g
  end

  test "tesistas excluye grade sin tesis" do
    g = crear_grade(graduate_status: :cursante)
    refute_includes Grade.tesistas, g
  end

  test "tesistas excluye tesis en proceso INACTIVO" do
    periodo_otro     = Period.create!(year: 2024, period_type: @period_type)
    proceso_inactivo = AcademicProcess.create!(school: @school, period: periodo_otro,
                                               max_credits: 24, max_subjects: 6, active: false)
    g = crear_grade(graduate_status: :cursante)
    inscribir_tesis(g, proceso: proceso_inactivo)
    refute_includes Grade.tesistas, g
  end

  test "tesistas excluye tesis retirada" do
    g = crear_grade(graduate_status: :cursante)
    inscribir_tesis(g, status: :retirado)
    refute_includes Grade.tesistas, g
  end

  test "tesistas excluye grade ya posible_graduando" do
    g = crear_grade(graduate_status: :posible_graduando)
    inscribir_tesis(g)
    refute_includes Grade.tesistas, g
  end

  test "tesis_activa devuelve el AcademicRecord de tesis activo" do
    g = crear_grade(graduate_status: :cursante)
    ar = inscribir_tesis(g)
    assert_equal ar, g.tesis_activa
  end

  # ======================================================================
  # SCOPE :of_schools
  # ======================================================================

  test "of_schools filtra por escuela del study_plan" do
    g_mio = crear_grade

    otra_fac    = Faculty.create!(name: "Otra #{@uid}", code: "OF#{@uid}",
                                  contact_email: "of#{@uid}@test.com", coes_boss_name: "X #{@uid}")
    otra_esc    = School.create!(name: "Otra Esc #{@uid}", code: "OE#{@uid}", faculty: otra_fac)
    otro_plan   = StudyPlan.create!(code: "OP#{@uid}", name: "Otro Plan #{@uid}", school: otra_esc)
    g_otro      = crear_grade(plan: otro_plan)

    resultado = Grade.of_schools([@school.id])
    assert_includes resultado, g_mio
    refute_includes resultado, g_otro
  end
end
