require "test_helper"

# Resetear contraseña (la cédula pasa a ser la clave): botón en el detalle de profesores y admins,
# y el endpoint exige gestionar el rol más alto del usuario. Antes bastaba con ser admin.
class ResetClaveTest < ActionDispatch::IntegrationTest
  setup do
    @uid = SecureRandom.hex(4)
    faculty = Faculty.create!(name: "Fac RC #{@uid}", code: "FRC#{@uid}", contact_email: "frc#{@uid}@test.com", coes_boss_name: "Jefe #{@uid}")
    @school = School.create!(name: "Esc RC #{@uid}", code: "ERC#{@uid}", faculty: faculty)
    @jefe = admin('Jefe', :jefe_control_estudio)
    dpto = Departament.create!(name: "Dpto RC #{@uid}", school: @school)
    @profe = Teacher.create!(user: usuario('Profe'), departament: dpto)
    @otro_admin = admin('Asist', :asistente)
  end

  def usuario(nombre)
    User.create!(ci: "#{rand(10**8)}", email: "#{nombre.downcase}#{@uid}@test.com", first_name: nombre, last_name: 'Clave',
                 password: 'password123', updated_password: true)
  end

  def admin(nombre, rol)
    admin = Admin.new(user: usuario(nombre), role: rol)
    admin.env_auths.build(env_authorizable: @school)
    admin.save!
    admin
  end

  def entrar(user)
    post user_session_path, params: {user: {ci: user.ci, password: 'password123'}}
  end

  def clave_es_la_cedula?(user)
    user.reload.valid_password?(user.ci)
  end

  test "el jefe ve el botón en el detalle de un profesor y de un admin, y resetea" do
    entrar @jefe.user

    get "/admin/teacher/#{@profe.id}"
    assert_select "a[href='/users/#{@profe.user.id}/reset_password']", /Resetear contraseña/
    get "/admin/admin/#{@otro_admin.id}"
    assert_select "a[href='/users/#{@otro_admin.user.id}/reset_password']", /Resetear contraseña/

    get "/users/#{@profe.user.id}/reset_password"
    assert clave_es_la_cedula?(@profe.user)
    assert_not @profe.user.updated_password
  end

  test "un asistente de sólo lectura no ve el botón ni puede resetear" do
    lector = @otro_admin
    lector.authorizeds.create!(authorizable: Authorizable.find_by(klazz: 'Teacher') ||
                              Authorizable.create!(klazz: 'Teacher', area_authorizable: AreaAuthorizable.create!(name: "Área RC #{@uid}")), can_read: true)
    entrar lector.user

    get "/admin/teacher/#{@profe.id}"
    assert_select "a[href='/users/#{@profe.user.id}/reset_password']", 0

    get "/users/#{@jefe.user.id}/reset_password"
    assert_not clave_es_la_cedula?(@jefe.user)
    get "/users/#{@profe.user.id}/reset_password"
    assert_not clave_es_la_cedula?(@profe.user)
  end

  test "a un desarrollador sólo lo resetea otro desarrollador" do
    dev = users(:admin_user)
    assert_not @jefe.puede_resetear_clave?(dev)
    assert dev.admin.puede_resetear_clave?(@jefe.user)

    entrar @jefe.user
    get "/users/#{dev.id}/reset_password"
    assert_not clave_es_la_cedula?(dev)
  end
end
