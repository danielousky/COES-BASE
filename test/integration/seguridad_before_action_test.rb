require "test_helper"

# `before_action :logged_as_admin?` no protegía nada: el predicado devuelve true/false y un before_action
# sólo corta si redirige o renderiza. Cualquier usuario autenticado (un estudiante) llegaba a la acción.
# Ver docs/SEGURIDAD_before_action_predicados.md.
#
# Por cada endpoint: quien no debe recibe 403/redirect y el dato no cambia; quien sí debe, sigue pudiendo.
class SeguridadBeforeActionTest < ActionDispatch::IntegrationTest
  JS_JSON = {'Accept' => 'application/json, text/javascript, */*; q=0.01', 'X-Requested-With' => 'XMLHttpRequest'}.freeze

  setup do
    @uid = SecureRandom.hex(4)
    faculty = Faculty.create!(name: "Fac Seg #{@uid}", code: "FS#{@uid}", contact_email: "fs#{@uid}@test.com", coes_boss_name: "Jefe #{@uid}")
    @school = School.create!(name: "Esc Seg #{@uid}", code: "ES#{@uid}", faculty: faculty)
    @otra_escuela = School.create!(name: "Otra Seg #{@uid}", code: "OS#{@uid}", faculty: faculty)
    plan = StudyPlan.create!(code: "SPS#{@uid}", name: "Plan Seg #{@uid}", school: @school)
    tipo = PeriodType.create!(code: "S#{@uid}", name: "Período #{@uid}")
    @proceso = AcademicProcess.create!(school: @school, period: Period.create!(year: 2025, period_type: tipo), max_credits: 24, max_subjects: 6)

    area = Area.create!(name: "Area #{@uid}", school: @school)
    @dpto = Departament.create!(name: "Dpto #{@uid}", school: @school)
    @dpto.areas << area
    tipo_asig = SubjectType.find_or_create_by!(code: "SEG#{('a'..'z').to_a.sample(8).join}") { |st| st.name = "OBLIG #{@uid}" }
    @subject = Subject.create!(code: "MS#{@uid}", name: "Materia #{@uid}", ordinal: 1, subject_type: tipo_asig,
                               qualification_type: :numerica, unit_credits: 3, area: area, departament: @dpto, school: @school)

    @profe = Teacher.create!(user: usuario('Profe'), departament: @dpto)
    @profe_ajeno = Teacher.create!(user: usuario('Ajeno'), departament: @dpto)
    course = Course.create!(academic_process: @proceso, subject: @subject)
    @section = Section.create!(course: course, code: 'A', capacity: 30, modality: :nota_final, teacher: @profe)

    @estudiante = usuario('Est')
    grade = Grade.create!(student: Student.create!(user: @estudiante), study_plan: plan,
                          admission_type: AdmissionType.create!(name: "Adm #{@uid}", code: "AS#{@uid}"), current_permanence_status: :regular)
    eap = EnrollAcademicProcess.create!(grade: grade, academic_process: @proceso, enroll_status: :confirmado, permanence_status: :regular)
    @record = AcademicRecord.create!(section: @section, enroll_academic_process: eap)

    @jefe_otra = admin('JefeOtra', :jefe_control_estudio, @otra_escuela)
    @asistente = admin('Asist', :asistente, @school)
  end

  def usuario(nombre)
    User.create!(ci: "#{rand(10**8)}", email: "#{nombre.downcase}#{@uid}@test.com", first_name: nombre, last_name: 'Seg',
                 password: 'password123', updated_password: true)
  end

  def admin(nombre, rol, escuela)
    admin = Admin.new(user: usuario(nombre), role: rol)
    admin.env_auths.build(env_authorizable: escuela)
    admin.save!
    admin
  end

  # Por el formulario de verdad, para que after_sign_in_path_for fije session[:rol]
  def entrar(user)
    delete destroy_user_session_path # con sesión abierta, Devise no cambia de usuario
    post user_session_path, params: {user: {ci: user.ci, password: 'password123'}}
  end

  def assert_rechazado
    assert(response.redirect? || response.forbidden?, "Se esperaba 403 o redirect y respondió #{response.status}")
  end

  def calificar(valor, tipo = 'final')
    patch "/qualifications/#{@record.id}", params: {qualification: {value: valor, type_q: tipo}}, headers: JS_JSON
  end

  def calificar_parcial(valor)
    patch "/partial_qualifications/#{@record.id}", params: {partial_qualification: {value: valor, partial: 'primer_lapso'}}, headers: JS_JSON
  end

  # == authorizeds#update_authorize: escalada de privilegios

  test "un estudiante no puede reescribir los permisos de un admin" do
    entrar @estudiante
    post '/authorizeds/update_authorize', params: {id: @asistente.id, "model#{authorizable('Admin').id}": {can_read: 1, can_update: 1}}

    assert_rechazado
    assert_empty @asistente.authorizeds.reload
  end

  test "un asistente sin permiso sobre Admin no puede darse permisos a sí mismo" do
    entrar @asistente.user
    post '/authorizeds/update_authorize', params: {id: @asistente.id, "model#{authorizable('Admin').id}": {can_create: 1, can_update: 1}}

    assert_rechazado
    assert_empty @asistente.authorizeds.reload
  end

  test "el desarrollador sí actualiza los permisos de un asistente" do
    entrar users(:admin_user)
    post '/authorizeds/update_authorize', params: {id: @asistente.id, "model#{authorizable('Admin').id}": {can_read: 1}}

    assert_redirected_to "/admin/admin/#{@asistente.id}"
    assert @asistente.authorizeds.reload.find_by(authorizable: authorizable('Admin')).can_read?
  end

  # == qualifications#update y partial_qualifications#update: cambiar notas

  test "un estudiante no puede ponerse nota" do
    entrar @estudiante
    calificar 20
    assert_rechazado
    calificar_parcial 20
    assert_rechazado
    assert_empty @record.reload.qualifications
    assert_empty @record.partial_qualifications
  end

  test "un profesor no puede calificar una sección que no es suya" do
    entrar @profe_ajeno.user
    calificar 20
    assert_rechazado
    calificar_parcial 20
    assert_rechazado
    assert_empty @record.reload.qualifications
    assert_empty @record.partial_qualifications
  end

  test "el profesor de la sección sí califica" do
    entrar @profe.user
    calificar 15
    assert_response :success
    assert_equal 15, @record.reload.qualifications.find_by(type_q: :final).value

    calificar_parcial 12
    assert_response :success
    assert_equal 12, @record.partial_qualifications.find_by(partial: :primer_lapso).value
  end

  test "el profesor no cambia notas de una sección ya calificada" do
    @record.qualifications.create!(type_q: :final, value: 10, definitive: true)
    @section.update_column(:qualified, true)
    entrar @profe.user
    calificar 20

    assert_rechazado
    assert_equal 10, @record.reload.qualifications.find_by(type_q: :final).value
  end

  test "un admin de otra escuela no puede calificar" do
    entrar @jefe_otra.user
    calificar 20
    assert_rechazado
    assert_empty @record.reload.qualifications
  end

  test "un asistente sin permiso sobre secciones no puede calificar" do
    entrar @asistente.user
    calificar 20
    assert_rechazado
    assert_empty @record.reload.qualifications
  end

  test "el admin desarrollador sí califica" do
    entrar users(:admin_user)
    calificar 18
    assert_response :success
    assert_equal 18, @record.reload.qualifications.find_by(type_q: :final).value
  end

  # == schools: cambiar la escuela (abrir/cerrar inscripción) y exportar todos los expedientes

  test "un estudiante no puede abrir la inscripción ni exportar los expedientes de la escuela" do
    entrar @estudiante
    put "/schools/#{@school.id}", params: {school: {enroll_process_id: @proceso.id}}
    assert_rechazado
    assert_nil @school.reload.enroll_process_id

    get "/schools/#{@school.id}/export_grades.xls"
    assert_rechazado
  end

  test "un admin de otra escuela no puede cambiar esta escuela" do
    entrar @jefe_otra.user
    put "/schools/#{@school.id}", params: {school: {enroll_process_id: @proceso.id}}, as: :json
    assert_rechazado
    assert_nil @school.reload.enroll_process_id
  end

  test "el admin abre la inscripción de su escuela" do
    entrar users(:admin_user)
    put "/schools/#{@school.id}", params: {school: {enroll_process_id: @proceso.id}}, as: :json
    assert_response :success
    assert_equal @proceso.id, @school.reload.enroll_process_id
  end

  # == export: datos personales y académicos

  test "un estudiante no puede descargar exportes" do
    grade = @record.grade
    entrar @estudiante

    get "/export/history_grade/#{grade.id}.xls"
    assert_rechazado
    get "/export/xls/#{@proceso.id}.xls", params: {grades_others: true}
    assert_rechazado
  end

  test "un admin de otra escuela no descarga exportes de esta" do
    entrar @jefe_otra.user

    get "/export/history_grade/#{@record.grade.id}.xls"
    assert_response :forbidden
    get "/export/xls/#{@proceso.id}.xls", params: {grades_others: true}
    assert_response :forbidden
    get "/schools/#{@school.id}/export_grades.xls"
    assert_response :forbidden
  end

  test "el admin descarga el histórico de un expediente" do
    entrar users(:admin_user)
    get "/export/history_grade/#{@record.grade.id}.xls"
    assert_response :success
  end

  # == enrollment_days: citas horarias

  test "un estudiante no puede crear ni borrar citas horarias" do
    dia = EnrollmentDay.create!(academic_process: @proceso, start: 1.day.from_now.change(hour: 8), total_duration_hours: 4,
                                max_grades: 10, slot_duration_minutes: 30)
    entrar @estudiante

    assert_no_difference 'EnrollmentDay.count' do
      post '/enrollment_days', params: {enrollment_day: {academic_process_id: @proceso.id, start: 2.days.from_now.change(hour: 8),
                                                         total_duration_hours: 4, max_grades: 10, slot_duration_minutes: 30}}
      assert_rechazado
      delete "/enrollment_days/#{dia.id}"
      assert_rechazado
      delete "/enrollment_days/#{dia.id}/destroy_all"
      assert_rechazado
    end
    get "/enrollment_days/#{dia.id}/export.xls"
    assert_rechazado
  end

  test "un admin de otra escuela no crea citas horarias en esta" do
    entrar @jefe_otra.user
    assert_no_difference 'EnrollmentDay.count' do
      post '/enrollment_days', params: {enrollment_day: {academic_process_id: @proceso.id, start: 2.days.from_now.change(hour: 8),
                                                         total_duration_hours: 4, max_grades: 10, slot_duration_minutes: 30}}
    end
    assert_rechazado
  end

  test "el admin borra una jornada de cita horaria" do
    dia = EnrollmentDay.create!(academic_process: @proceso, start: 1.day.from_now.change(hour: 8), total_duration_hours: 4,
                                max_grades: 10, slot_duration_minutes: 30)
    entrar users(:admin_user)
    delete "/enrollment_days/#{dia.id}"
    assert_not EnrollmentDay.exists?(dia.id)
  end

  # == session_admin y subjects

  test "un estudiante no puede cambiar el período de la sesión de admin" do
    entrar @estudiante
    post '/session_admin/change_period_session', params: {nuevo: '2099-X'}
    assert_rechazado
    assert_nil flash[:success]
  end

  test "un estudiante no puede ver la ficha de una asignatura del admin" do
    entrar @estudiante
    get "/subjects/#{@subject.id}"
    assert_rechazado
  end

  private

  def authorizable(klazz)
    Authorizable.find_by(klazz: klazz) ||
      Authorizable.create!(klazz: klazz, area_authorizable: AreaAuthorizable.create!(name: "Área Seg #{@uid}"))
  end
end
