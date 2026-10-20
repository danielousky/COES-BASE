require "test_helper"

# Mapa de prelaciones: vista Estructura del plan y endpoints JSON que usa mapa_prelaciones_controller.js.
#
# Cubre:
#   - la vista Estructura dibuja el mapa con los datos de la escuela
#   - crear: guarda; si parece al revés responde 409 y sólo guarda con confirmar; ciclo => 422
#   - invertir y quitar
#   - un estudiante (sin rol admin) no puede crear ni borrar prelaciones (antes el destroy no lo impedía)
#   - un admin de otra escuela no puede tocar prelaciones ajenas
#   - "Ver como estudiante" devuelve la oferta de Grade#asignaturas_ofertables_segun_dependencia
class MapaPrelacionesTest < ActionDispatch::IntegrationTest
  setup do
    @uid = SecureRandom.hex(4)
    faculty = Faculty.create!(name: "Fac Mapa #{@uid}", code: "FM#{@uid}",
                              contact_email: "fm#{@uid}@test.com", coes_boss_name: "Jefe #{@uid}")
    @school = School.create!(name: "Esc Mapa #{@uid}", code: "EM#{@uid}", faculty: faculty)
    @plan = StudyPlan.create!(code: "SPM#{@uid}", name: "Plan Mapa #{@uid}", school: @school, structure: :por_dependencia)
    @area = Area.create!(name: "Area #{@uid}", school: @school)
    @departament = Departament.create!(name: "Dpto #{@uid}", school: @school)
    @departament.areas << @area
    @tipo = SubjectType.find_or_create_by!(code: "MAP#{("a".."z").to_a.sample(8).join}") { |st| st.name = "OBLIG #{@uid}" }

    @uno = materia('Curso Uno', 1)
    @dos = materia('Curso Dos', 2)
    @cinco = materia('Curso Cinco', 5)
  end

  def materia(nombre, ordinal, school: @school)
    area = school == @school ? @area : Area.create!(name: "Area #{rand(10**6)}", school: school)
    dpto = school == @school ? @departament : Departament.create!(name: "Dpto #{rand(10**6)}", school: school).tap { |d| d.areas << area }
    Subject.create!(code: "M#{@uid}#{rand(10**6)}", name: "#{nombre} #{@uid}", ordinal: ordinal, subject_type: @tipo,
                    qualification_type: :numerica, unit_credits: 3, area: area, departament: dpto, school: school)
  end

  # Entra por el formulario de verdad para que after_sign_in_path_for fije session[:rol]
  def entrar(user, clave = 'password123')
    post user_session_path, params: {user: {ci: user.ci, password: clave}}
  end

  def entrar_como_admin
    entrar users(:admin_user)
  end

  def json
    JSON.parse(response.body)
  end

  def crear(materia, previa, confirmar: false)
    params = {subject_link: {prelate_subject_id: materia.id, depend_subject_id: previa.id}}
    params[:confirmar] = '1' if confirmar
    post subject_links_path(format: :json), params: params, as: :json
  end

  test "la vista Estructura dibuja el mapa con las materias y prelaciones de la escuela" do
    SubjectLink.create!(prelate_subject: @dos, depend_subject: @uno)
    entrar_como_admin

    get "/admin/study_plan/#{@plan.id}/structure"
    assert_response :success
    assert_select "[data-controller='mapa-prelaciones']" do |nodos|
      datos = JSON.parse(nodos.first['data-mapa-prelaciones-datos-value'])
      assert_equal [@uno.id, @dos.id, @cinco.id].sort, datos['materias'].map { |m| m['id'] }.sort
      assert_equal [[@dos.id, @uno.id]], datos['prelaciones'].map { |l| [l['materia'], l['previa']] }
    end
  end

  test "crear una prelación hacia adelante la guarda" do
    entrar_como_admin
    crear(@dos, @uno)

    assert_response :success
    assert_equal({'materia' => @dos.id, 'previa' => @uno.id, 'advertencia' => nil}, json.except('id'))
    assert SubjectLink.exists?(prelate_subject_id: @dos.id, depend_subject_id: @uno.id)
  end

  test "si parece al revés responde 409 y sólo guarda al confirmar" do
    entrar_como_admin
    crear(@uno, @cinco)
    assert_response :conflict
    assert json['requiere_confirmacion']
    assert_match(/es de 5\.º/, json['advertencia'])
    assert_not SubjectLink.exists?(prelate_subject_id: @uno.id, depend_subject_id: @cinco.id)

    crear(@uno, @cinco, confirmar: true)
    assert_response :success
    assert SubjectLink.exists?(prelate_subject_id: @uno.id, depend_subject_id: @cinco.id)
  end

  test "una prelación circular se rechaza aunque se confirme" do
    SubjectLink.create!(prelate_subject: @dos, depend_subject: @uno)
    entrar_como_admin
    crear(@uno, @dos, confirmar: true)

    assert_response :unprocessable_entity
    assert_match(/circular/, json['error'])
  end

  test "invertir corrige el sentido y deja historial" do
    link = SubjectLink.create!(prelate_subject: @uno, depend_subject: @cinco)
    entrar_como_admin
    patch invertir_subject_link_path(link, format: :json), as: :json

    assert_response :success
    assert_equal [@cinco.id, @uno.id], link.reload.values_at(:prelate_subject_id, :depend_subject_id)
    assert_equal 'update', PaperTrail::Version.where(item_type: 'SubjectLink', item_id: link.id).last.event
  end

  test "quitar una prelación" do
    link = SubjectLink.create!(prelate_subject: @dos, depend_subject: @uno)
    entrar_como_admin
    delete subject_link_path(link, format: :json)

    assert_response :success
    assert_not SubjectLink.exists?(link.id)
  end

  test "un estudiante no puede crear ni borrar prelaciones" do
    link = SubjectLink.create!(prelate_subject: @dos, depend_subject: @uno)
    user = User.create!(ci: "E#{@uid}", email: "e#{@uid}@test.com", first_name: 'Est', last_name: 'Udiante',
                        password: 'password123', updated_password: true)
    Student.create!(user: user)
    entrar user

    delete subject_link_path(link, format: :json)
    assert_response :forbidden
    assert SubjectLink.exists?(link.id)

    crear(@cinco, @dos)
    assert_response :forbidden
  end

  test "un admin de otra escuela no puede tocar prelaciones de esta" do
    otra = School.create!(name: "Otra #{@uid}", code: "OT#{@uid}", faculty: @school.faculty)
    user = User.create!(ci: "A#{@uid}", email: "a#{@uid}@test.com", first_name: 'Jefe', last_name: 'Otra',
                        password: 'password123', updated_password: true)
    admin = Admin.new(user: user, role: :jefe_control_estudio)
    admin.env_auths.build(env_authorizable: otra)
    admin.save!
    entrar user

    crear(@dos, @uno)
    assert_response :forbidden
    assert_not SubjectLink.exists?(prelate_subject_id: @dos.id, depend_subject_id: @uno.id)
  end

  test "ver como estudiante devuelve aprobadas y oferta según COES" do
    SubjectLink.create!(prelate_subject: @dos, depend_subject: @uno)
    user = User.create!(ci: "S#{@uid}", email: "s#{@uid}@test.com", first_name: 'Ana', last_name: 'Pérez',
                        password: 'password123', updated_password: true)
    student = Student.create!(user: user)
    admission = AdmissionType.create!(name: "Adm #{@uid}", code: "AD#{@uid}")
    grade = Grade.create!(student: student, study_plan: @plan, admission_type: admission)
    entrar_como_admin

    get oferta_estudiante_study_plan_path(@plan, format: :json), params: {ci: user.ci}
    assert_response :success
    assert_equal [], json['aprobadas']
    assert_equal grade.asignaturas_ofertables_segun_dependencia.ids.sort, json['ofertables'].sort
    assert_not_includes json['ofertables'], @dos.id, 'Curso Dos exige Curso Uno, que no ha aprobado'

    get oferta_estudiante_study_plan_path(@plan, format: :json), params: {ci: 'no-existe'}
    assert_response :not_found
  end
end
