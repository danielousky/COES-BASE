require "test_helper"

# Simulador de inscripción (/admin/grade/:id/simular_inscripcion): CE ve lo que el estudiante vería al inscribirse.
# La lista y la capa del mapa salen de OfertaInscripcion con como_estudiante: true, igual que su formulario.
class SimularInscripcionTest < ActionDispatch::IntegrationTest
  setup do
    @uid = SecureRandom.hex(4)
    faculty = Faculty.create!(name: "Fac SI #{@uid}", code: "FSI#{@uid}", contact_email: "fsi#{@uid}@test.com", coes_boss_name: "Jefe #{@uid}")
    @school = School.create!(name: "Esc SI #{@uid}", code: "ESI#{@uid}", faculty: faculty)
    @plan = StudyPlan.create!(code: "SPSI#{@uid}", name: "Plan SI #{@uid}", school: @school, structure: :por_dependencia, modality: :Semestral)
    @tipo = SubjectType.create!(code: "SI#{("a".."z").to_a.sample(8).join}", name: "Oblig #{@uid}")
    tipo_periodo = PeriodType.create!(code: "S#{@uid}", name: "Período #{@uid}")
    @anterior = AcademicProcess.create!(school: @school, period: Period.create!(year: 2024, period_type: tipo_periodo), modality: :Semestral,
                                        max_credits: 24, max_subjects: 6)
    @proceso = AcademicProcess.create!(school: @school, period: Period.create!(year: 2025, period_type: tipo_periodo), modality: :Semestral,
                                       max_credits: 24, max_subjects: 6, process_before: @anterior, enroll: true)

    @uno = materia('Uno', 1)
    @dos = materia('Dos', 2)          # exige Uno: el estudiante no la ve, CE sí
    @sin_seccion = materia('Vacia', 1) # ofertada pero sin secciones: no aparece en ninguna lista
    SubjectLink.create!(prelate_subject: @dos, depend_subject: @uno)
    [@uno, @dos].each do |m|
      Section.create!(course: Course.create!(subject: m, academic_process: @proceso), code: "A", capacity: 30, modality: :nota_final, qualified: false)
    end
    Course.create!(subject: @sin_seccion, academic_process: @proceso)

    user = User.create!(ci: "#{rand(10**8)}", email: "si#{@uid}@test.com", first_name: 'Ana', last_name: 'Simulada',
                        password: 'password123', updated_password: true)
    @grade = Grade.create!(student: Student.create!(user: user), study_plan: @plan,
                           admission_type: AdmissionType.create!(name: "Adm #{@uid}", code: "ASI#{@uid}"))
  end

  def materia(nombre, ordinal)
    area = Area.create!(name: "Area #{nombre} #{@uid}", school: @school)
    dpto = Departament.create!(name: "Dpto #{nombre} #{@uid}", school: @school).tap { |d| d.areas << area }
    Subject.create!(code: "SI#{nombre}#{@uid}", name: "#{nombre} #{@uid}", ordinal: ordinal, subject_type: @tipo,
                    qualification_type: :numerica, unit_credits: 3, area: area, departament: dpto, school: @school)
  end

  def entrar(user)
    post user_session_path, params: {user: {ci: user.ci, password: 'password123'}}
  end

  def ruta
    "/admin/grade/#{@grade.id}/simular_inscripcion"
  end

  test "muestra si puede inscribirse hoy y la misma oferta que vería el estudiante" do
    entrar users(:admin_user)
    get ruta

    assert_response :success
    assert_select '.alert-success', /Puede inscribirse ahora: el período no usa cita horaria/
    assert_select "template[data-mapa-prelaciones-target='lista']" do |plantilla|
      assert_match "Le aparecerían 1 materias (3 UC)", plantilla.first.inner_html
      assert_match @uno.code, plantilla.first.inner_html
      assert_no_match @dos.code, plantilla.first.inner_html
      assert_match "CE ve además 1 que el estudiante no ve", plantilla.first.inner_html
    end

    real = OfertaInscripcion.con_secciones(OfertaInscripcion.new(@grade, @proceso, como_estudiante: true).cursos).map(&:subject_id)
    assert_select "[data-controller='mapa-prelaciones']" do |nodos|
      periodo = JSON.parse(nodos.first['data-mapa-prelaciones-estudiante-value'])['periodo']
      assert_equal real, periodo['ofertadas']
      assert_equal [@uno.id], periodo['ofertadas']
      assert_equal [@dos.id, @uno.id].sort, periodo['programadas'].sort
      assert_equal [], periodo['inscritas']
    end
  end

  test "el detalle del estudiante lleva al simulador junto al botón de inscribir" do
    entrar users(:admin_user)
    get "/admin/student/#{@grade.student_id}"

    assert_response :success
    assert_select ".col-md-8 a[href='#{ruta}']", /Simular inscripción/
  end

  test "se puede simular otro período de la escuela" do
    entrar users(:admin_user)
    get ruta, params: {academic_process_id: @anterior.id}

    assert_response :success
    assert_select '.alert-warning', /no tiene la inscripción abierta/
  end

  test "un admin de otra escuela ve acceso restringido" do
    otra = School.create!(name: "Otra #{@uid}", code: "OT#{@uid}", faculty: @school.faculty)
    user = User.create!(ci: "A#{@uid}", email: "a#{@uid}@test.com", first_name: 'Jefe', last_name: 'Otra',
                        password: 'password123', updated_password: true)
    admin = Admin.new(user: user, role: :jefe_control_estudio)
    admin.env_auths.build(env_authorizable: otra)
    admin.save!
    entrar user
    get ruta

    assert_select 'h1', /Acceso Restringido/
    assert_select "[data-controller='mapa-prelaciones']", 0
  end

  test "un estudiante no entra al simulador" do
    entrar @grade.student.user
    assert_raises(CanCan::AccessDenied) { get ruta }
  end
end
