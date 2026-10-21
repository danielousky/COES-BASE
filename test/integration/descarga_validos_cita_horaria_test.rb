require "test_helper"

# Cita Horaria: descargar la pestaña "Válidos para Aplicar" igual que "No Aplican" (export#xls).
class DescargaValidosCitaHorariaTest < ActionDispatch::IntegrationTest
  setup do
    @uid = SecureRandom.hex(4)
    faculty = Faculty.create!(name: "Fac CH #{@uid}", code: "FCH#{@uid}", contact_email: "fch#{@uid}@test.com", coes_boss_name: "Jefe #{@uid}")
    school = School.create!(name: "Esc CH #{@uid}", code: "ECH#{@uid}", faculty: faculty)
    plan = StudyPlan.create!(code: "SPCH#{@uid}", name: "Plan CH #{@uid}", school: school)
    tipo = PeriodType.create!(code: "C#{@uid}", name: "Período #{@uid}")
    anterior = AcademicProcess.create!(school: school, period: Period.create!(year: 2024, period_type: tipo), max_credits: 24, max_subjects: 6)
    @proceso = AcademicProcess.create!(school: school, period: Period.create!(year: 2025, period_type: tipo), max_credits: 24, max_subjects: 6,
                                       process_before: anterior)

    admision = AdmissionType.create!(name: "Adm #{@uid}", code: "ACH#{@uid}")
    @regular = estudiante('Ana', 'Regular', :regular, plan, admision)
    @desertor = estudiante('Beto', 'Desertor', :desertor, plan, admision)
    # La permanencia del expediente se recalcula con la de su última inscripción
    {@regular => :regular, @desertor => :desertor}.each do |grade, permanencia|
      EnrollAcademicProcess.create!(grade: grade, academic_process: anterior, enroll_status: :confirmado, permanence_status: permanencia)
    end
  end

  def estudiante(nombre, apellido, permanencia, plan, admision)
    user = User.create!(ci: "#{rand(10**8)}", email: "#{nombre}#{@uid}@test.com", first_name: nombre, last_name: apellido,
                        password: 'password123', updated_password: true)
    Grade.create!(student: Student.create!(user: user), study_plan: plan, admission_type: admision, current_permanence_status: permanencia)
  end

  def entrar(user)
    post user_session_path, params: {user: {ci: user.ci, password: 'password123'}}
  end

  test "el admin descarga los válidos para aplicar con las columnas de la pestaña" do
    entrar users(:admin_user)
    get "/export/xls/#{@proceso.id}.xls", params: {grades_valid: true}

    assert_response :success
    assert_match "Validos para Cita Horaria", response.headers['Content-Disposition']
    filas = CSV.parse(response.body)
    assert_equal ["Estado Insc #{@proceso.process_name}", 'Est. Permanencia', 'Sede', 'Cédula', 'Apellido y Nombre', 'Correo', 'Eficiencia', 'Promedio', 'Ponderado'], filas.first
    assert_equal [@regular.user.ci], filas.drop(1).map { |fila| fila[3] }
    assert_equal ['Sin Inscripción', 'Regular'], filas.second.first(2)
    assert_equal @regular.user.email, filas.second[5]
  end

  test "la pestaña Válidos para Aplicar tiene su botón Descargar" do
    entrar users(:admin_user)
    get "/admin/academic_process/#{@proceso.id}/enrollment_day"

    assert_response :success
    assert_select "#withoutAppointment a[href='/export/xls/#{@proceso.id}.xls?grades_valid=true']", text: /Descargar/
    assert_select "#otherGrades a[href='/export/xls/#{@proceso.id}.xls?grades_others=true']", text: /Descargar/
  end

  test "un estudiante no puede descargar listados de cita horaria" do
    entrar @regular.user
    get "/export/xls/#{@proceso.id}.xls", params: {grades_valid: true}
    assert_response :forbidden

    get "/export/xls/#{@proceso.id}.xls", params: {grades_others: true}
    assert_response :forbidden
  end
end
