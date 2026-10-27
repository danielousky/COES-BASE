require "test_helper"

# Barrido de controladores sin ningún filtro de rol (paso 4 de docs/SEGURIDAD_before_action_predicados.md).
# Antes, cualquier usuario autenticado llegaba a create/update/destroy de los scaffolds, y en los flujos que sí usan
# estudiantes y profesores no se revisaba sobre qué registro se actuaba (el id ajeno pasaba).
#
# Por cada caso: quien no debe recibe 403/redirect y el dato no cambia; el flujo legítimo sigue funcionando.
class SeguridadBarridoTest < ActionDispatch::IntegrationTest
  JS_JSON = {'Accept' => 'application/json, text/javascript, */*; q=0.01', 'X-Requested-With' => 'XMLHttpRequest'}.freeze

  setup do
    @uid = SecureRandom.hex(4)
    faculty = Faculty.create!(name: "Fac Barr #{@uid}", code: "FB#{@uid}", contact_email: "fb#{@uid}@test.com", coes_boss_name: "Jefe #{@uid}")
    @school = School.create!(name: "Esc Barr #{@uid}", code: "EB#{@uid}", faculty: faculty)
    @otra_escuela = School.create!(name: "Otra Barr #{@uid}", code: "OB#{@uid}", faculty: faculty)
    @plan = StudyPlan.create!(code: "SPB#{@uid}", name: "Plan Barr #{@uid}", school: @school, modality: :Semestral)
    tipo = PeriodType.create!(code: "B#{@uid}", name: "Período #{@uid}")
    # Inscripción abierta, sin cita horaria: el estudiante nuevo puede inscribirse por su cuenta
    @proceso = AcademicProcess.create!(school: @school, period: Period.create!(year: 2026, period_type: tipo), modality: :Semestral,
                                       max_credits: 24, max_subjects: 6, enroll: true)

    area = Area.create!(name: "Area #{@uid}", school: @school)
    dpto = Departament.create!(name: "Dpto #{@uid}", school: @school)
    dpto.areas << area
    tipo_asig = SubjectType.find_or_create_by!(code: "BAR#{('a'..'z').to_a.sample(8).join}") { |st| st.name = "OBLIG #{@uid}" }
    subject = Subject.create!(code: "MB#{@uid}", name: "Materia #{@uid}", ordinal: 1, subject_type: tipo_asig,
                              qualification_type: :numerica, unit_credits: 3, area: area, departament: dpto, school: @school)

    @profe = Teacher.create!(user: usuario('Profe'), departament: dpto)
    @profe_ajeno = Teacher.create!(user: usuario('Ajeno'), departament: dpto)
    @course = Course.create!(academic_process: @proceso, subject: subject)
    @section = Section.create!(course: @course, code: 'A', capacity: 30, modality: :nota_final, teacher: @profe)
    @admision = AdmissionType.create!(name: "Adm #{@uid}", code: "AB#{@uid}")

    @estudiante = usuario('Est')
    @grade = expediente(@estudiante)
    @eap = EnrollAcademicProcess.create!(grade: @grade, academic_process: @proceso, enroll_status: :reservado, permanence_status: :nuevo)
    @record = AcademicRecord.create!(section: @section, enroll_academic_process: @eap)

    @intruso = usuario('Intruso')
    @grade_intruso = expediente(@intruso)

    @jefe_otra = Admin.new(user: usuario('JefeOtra'), role: :jefe_control_estudio)
    @jefe_otra.env_auths.build(env_authorizable: @otra_escuela)
    @jefe_otra.save!
  end

  def usuario(nombre)
    User.create!(ci: "#{rand(10**8)}", email: "#{nombre.downcase}#{@uid}@test.com", first_name: nombre, last_name: 'Barr',
                 password: 'password123', updated_password: true)
  end

  def expediente(user)
    Grade.create!(student: Student.create!(user: user), study_plan: @plan, admission_type: @admision, current_permanence_status: :nuevo)
  end

  # Por el formulario de verdad, para que after_sign_in_path_for fije session[:rol]
  def entrar(user)
    delete destroy_user_session_path # con sesión abierta, Devise no cambia de usuario
    post user_session_path, params: {user: {ci: user.ci, password: 'password123'}}
  end

  def assert_rechazado
    assert(response.redirect? || response.forbidden?, "Se esperaba 403 o redirect y respondió #{response.status}")
  end

  # == Scaffolds de administración

  test "un estudiante no borra ni cambia datos de los scaffolds de administración" do
    tipo = PeriodType.create!(code: "Z#{@uid}", name: "Borrable #{@uid}")
    entrar @estudiante

    delete "/period_types/#{tipo.id}"
    assert_rechazado
    assert PeriodType.exists?(tipo.id)

    patch "/academic_processes/#{@proceso.id}", params: {academic_process: {max_credits: 99}}
    assert_rechazado
    assert_equal 24, @proceso.reload.max_credits

    delete "/faculties/#{@school.faculty.id}"
    assert_rechazado
    assert Faculty.exists?(@school.faculty.id)

    delete "/courses/#{@course.id}", params: {course: {academic_process_id: @proceso.id, subject_id: @course.subject_id}}, as: :json
    assert_rechazado
    assert Course.exists?(@course.id)
  end

  test "un admin de otra escuela no cambia el proceso académico de esta" do
    entrar @jefe_otra.user
    patch "/academic_processes/#{@proceso.id}", params: {academic_process: {max_credits: 99}}, as: :json
    assert_rechazado
    assert_equal 24, @proceso.reload.max_credits
  end

  test "el admin desarrollador cambia el proceso académico" do
    entrar users(:admin_user)
    patch "/academic_processes/#{@proceso.id}", params: {academic_process: {max_credits: 30}}, as: :json
    assert_response :success
    assert_equal 30, @proceso.reload.max_credits
  end

  test "un estudiante no descarga las actas generadas" do
    entrar @estudiante
    get '/academic_processes/download_actas', params: {filename: 'cualquiera.pdf'}
    assert_rechazado
    assert_no_match(/no existe/, flash[:danger].to_s, 'No debe llegar a buscar el archivo')
  end

  # == Inscripción del estudiante

  test "un estudiante no se confirma la inscripción a sí mismo" do
    entrar @estudiante
    post '/enroll_academic_processes/enroll', params: {grade_id: @grade.id, academic_process_id: @proceso.id, enroll_status: 'confirmado'}

    assert_redirected_to '/student_session/dashboard'
    assert_equal 'preinscrito', @eap.reload.enroll_status
  end

  test "el estudiante completa su preinscripción" do
    entrar @estudiante
    post '/enroll_academic_processes/enroll', params: {grade_id: @grade.id, academic_process_id: @proceso.id}

    assert_redirected_to '/student_session/dashboard'
    assert_equal 'preinscrito', @eap.reload.enroll_status
  end

  test "un estudiante no inscribe ni reserva cupo en el expediente de otro" do
    entrar @intruso
    post '/enroll_academic_processes/enroll', params: {grade_id: @grade.id, academic_process_id: @proceso.id}
    assert_rechazado
    assert_equal 'reservado', @eap.reload.enroll_status

    post '/enroll_academic_processes/reserve_space',
         params: {grade_id: @grade.id, academic_process_id: @proceso.id, course_id: @course.id, section_id: ''}, as: :json
    assert_response :forbidden
    assert AcademicRecord.exists?(@record.id), 'Liberar el cupo ajeno borraría su registro'
  end

  test "el estudiante reserva cupo en su expediente" do
    entrar @intruso
    post '/enroll_academic_processes/reserve_space',
         params: {grade_id: @grade_intruso.id, academic_process_id: @proceso.id, course_id: @course.id, section_id: @section.id}, as: :json
    assert_response :success
    assert @grade_intruso.academic_records.where(section_id: @section.id).exists?
  end

  test "un estudiante no reserva cupo si la inscripción no está abierta" do
    @proceso.update!(enroll: false)
    entrar @intruso
    post '/enroll_academic_processes/reserve_space',
         params: {grade_id: @grade_intruso.id, academic_process_id: @proceso.id, course_id: @course.id, section_id: @section.id}, as: :json
    assert_response :forbidden
    assert_not @grade_intruso.academic_records.exists?
  end

  test "un estudiante no borra su inscripción ni descarga constancias ajenas" do
    @eap.update_column(:enroll_status, EnrollAcademicProcess.enroll_statuses[:confirmado])
    entrar @estudiante
    delete "/enroll_academic_processes/#{@eap.id}"
    assert_rechazado
    assert EnrollAcademicProcess.exists?(@eap.id)

    entrar @intruso
    get "/enroll_academic_processes/#{@eap.id}.pdf"
    assert_rechazado
    assert_not @eap.versions.where(event: 'Se generó Constancia de Inscripción').exists?
  end

  test "el estudiante descarga su constancia de inscripción" do
    @eap.update_column(:enroll_status, EnrollAcademicProcess.enroll_statuses[:confirmado])
    entrar @estudiante
    get "/enroll_academic_processes/#{@eap.id}.pdf"
    assert_response :success
    assert_equal 'application/pdf', response.media_type
  end

  # == Expediente

  test "un estudiante no descarga el kardex de otro" do
    entrar @intruso
    get "/grades/#{@grade.id}/kardex.pdf"
    assert_rechazado
    assert_not @grade.versions.where(event: 'Se generó Kardex').exists?
  end

  test "el estudiante descarga su kardex" do
    entrar @estudiante
    get "/grades/#{@grade.id}/kardex.pdf"
    assert_response :success
    assert_equal 'application/pdf', response.media_type
  end

  # == Reporte de pago

  test "un estudiante no reporta un pago ya validado ni sobre la inscripción de otro" do
    cuenta = BankAccount.create!(code: "0102#{@uid}", holder: 'UCV', account_type: :corriente, bank: banco)
    @school.bank_accounts << cuenta
    entrar @estudiante

    post '/payment_reports', params: {payment_report: reporte(cuenta, @eap).merge(status: 'Validado')}
    assert_equal 'Pendiente', PaymentReport.where(payable: @eap).sole.status

    entrar @intruso
    assert_no_difference 'PaymentReport.count' do
      post '/payment_reports', params: {payment_report: reporte(cuenta, @eap)}
    end
    assert_rechazado
  end

  # == Secciones y registros académicos

  test "un estudiante no cierra el acta ni cambia el estado de su registro" do
    entrar @estudiante
    patch "/sections/#{@section.id}", params: {section: {qualified: true}}
    assert_rechazado
    assert_not @section.reload.qualified?

    patch "/academic_records/#{@record.id}", params: {academic_record: {status: :retirado}}
    assert_rechazado
    assert @record.reload.sin_calificar?
  end

  test "un profesor ajeno no marca inasistencia ni cierra el acta" do
    entrar @profe_ajeno.user
    patch "/academic_records/#{@record.id}", params: {academic_record: {status: :perdida_por_inasistencia}}, headers: JS_JSON
    assert_rechazado
    assert @record.reload.sin_calificar?

    @record.update!(status: :perdida_por_inasistencia)
    patch "/sections/#{@section.id}", params: {section: {qualified: true}}
    assert_rechazado
    assert_not @section.reload.qualified?
  end

  test "el profesor marca inasistencia y cierra el acta, sin cambiar más nada" do
    entrar @profe.user
    patch "/academic_records/#{@record.id}", params: {academic_record: {status: :perdida_por_inasistencia}}, headers: JS_JSON
    assert_response :success
    assert @record.reload.perdida_por_inasistencia?

    patch "/sections/#{@section.id}", params: {section: {qualified: true, teacher_id: @profe_ajeno.id, capacity: 1}}
    @section.reload
    assert @section.qualified?
    assert_equal [@profe.id, 30], [@section.teacher_id, @section.capacity]
  end

  test "el profesor no reabre el acta" do
    @section.update_column(:qualified, true)
    entrar @profe.user
    get "/sections/#{@section.id}/change_qualification_status", params: {section: {qualified: false}}
    assert_rechazado
    assert @section.reload.qualified?
  end

  # == Datos del estudiante y horarios

  test "un estudiante no ve ni cambia los datos ni la dirección de otro" do
    direccion = Address.create!(student: @grade.student, state: 'Miranda', municipality: 'Sucre', city: 'Caracas',
                                sector: 'Centro', street: 'Calle 1', house_type: :casa, house_name: 'Casa 1')
    entrar @intruso

    get "/students/#{@grade.student_id}/edit"
    assert_rechazado
    patch "/students/#{@grade.student_id}", params: {student: {origin_city: 'Intrusa'}}
    assert_rechazado
    assert_not_equal 'Intrusa', @grade.student.reload.origin_city

    patch "/students/#{@grade.student_id}/addresses/#{direccion.id}", params: {address: {street: 'Intrusa'}}
    assert_rechazado
    assert_equal 'Calle 1', direccion.reload.street
  end

  test "el estudiante actualiza sus datos" do
    entrar @estudiante
    patch "/students/#{@grade.student_id}", params: {student: {origin_city: 'Maracay'}}
    assert_equal 'Maracay', @grade.student.reload.origin_city
  end

  test "los horarios sólo los ve su dueño" do
    entrar @intruso
    get "/timetables/EnrollAcademicProcess/#{@eap.id}"
    assert_rechazado

    entrar @profe_ajeno.user
    get "/timetables/Teacher/#{@profe.id}", params: {academic_process_id: @proceso.id}
    assert_rechazado

    entrar @profe.user
    get "/timetables/Teacher/#{@profe.id}", params: {academic_process_id: @proceso.id}
    assert_response :success

    entrar @estudiante
    get "/timetables/EnrollAcademicProcess/#{@eap.id}"
    assert_response :success
  end

  private

  def banco
    Bank.create!(code: "B#{@uid}", name: "Banco #{@uid}")
  end

  def reporte(cuenta, payable)
    {amount: 10, transaction_id: '123456', transaction_type: 'transferencia', transaction_date: Date.current,
     origin_bank_id: cuenta.bank_id, receiving_bank_account_id: cuenta.id, payable_id: payable.id,
     payable_type: payable.class.name, owner_account_ci: '123', owner_account_name: 'PEREZ',
     voucher: fixture_file_upload('comprobante.png', 'image/png')}
  end
end
