require "test_helper"

# Smoke + flujo de la custom action RailsAdmin "graduacion".
# Verifica que action + vista (graduacion.html.haml) + helper del sidebar
# (main_navigation_with_extras) + ability rendericen de punta a punta, y que
# el POST de promoción/reversión opere sobre Grade.
#
# Se loguea como el admin desarrollador del fixture (schools_auh => School.all,
# ability => can :manage, :all), suficiente para acceder a /admin/graduacion.
class GraduacionActionTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin_user)
    sign_in @user
  end

  test "GET /admin/graduacion renderiza con tab por defecto" do
    get "/admin/graduacion"
    assert_response :success
    assert_select "h5", { text: /Proceso Graduación/ }
    assert_select "ul.nav-tabs"
  end

  test "el sidebar incluye el enlace al módulo (grupo Reportes)" do
    get "/admin/graduacion"
    assert_response :success
    assert_select "a.nav-link[href='/admin/graduacion']", { minimum: 1 },
                  "El sidebar debe incluir el enlace a Proceso Graduación"
  end

  test "cada tab del proceso renderiza sin error" do
    %w[tesistas posibles graduandos graduados].each do |tab|
      get "/admin/graduacion", params: { tab: tab }
      assert_response :success, "El tab #{tab} debe renderizar 200"
    end
  end

  test "tab inválido cae al default sin romper" do
    get "/admin/graduacion", params: { tab: "inexistente" }
    assert_response :success
  end

  test "descarga xlsx responde con content-type de spreadsheet" do
    assert_accion_sin_excepcion do
      get "/admin/graduacion", params: { tab: "graduados", download: "xlsx" }
    end
    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                 response.media_type
  end

  test "descarga xlsx de asignaturas desde el modal de recaudos" do
    grade = build_grade(:graduando)
    assert_accion_sin_excepcion do
      get "/admin/graduacion", params: { recaudos_for: grade.id, download: "xlsx" }
    end
    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                 response.media_type
  end

  test "POST promueve un Grade y redirige preservando el tab" do
    grade = build_grade(:posible_graduando)
    post "/admin/graduacion", params: { grade_id: grade.id, promote_to: "graduando", current_tab: "posibles" }
    assert_response :redirect
    assert_equal "graduando", grade.reload.graduate_status
  end

  test "POST revert devuelve un Grade" do
    grade = build_grade(:graduando)
    post "/admin/graduacion", params: { grade_id: grade.id, revert: "1", current_tab: "graduandos" }
    assert_response :redirect
    assert_equal "posible_graduando", grade.reload.graduate_status
  end

  private

  # RailsAdmin cuelga de un controller con ActionController::Live: si la acción
  # revienta después de send_data/redirect_to (p. ej. un `return` dentro del proc,
  # LocalJumpError), el cliente igual recibe 200/302. La excepción solo aparece en
  # la instrumentación, que es de donde sale el "Completed 500" del log.
  def assert_accion_sin_excepcion(&block)
    excepciones = []
    registrar = ->(*, payload) { excepciones << payload[:exception_object] if payload[:exception_object] }
    ActiveSupport::Notifications.subscribed(registrar, "process_action.action_controller", &block)
    assert_empty excepciones, "La acción levantó: #{excepciones.map(&:inspect).join(', ')}"
  end

  def build_grade(graduate_status)
    uid     = SecureRandom.hex(4)
    faculty = Faculty.create!(name: "Fac IT #{uid}", code: "FIT#{uid}",
                              contact_email: "fit#{uid}@test.com", coes_boss_name: "Jefe #{uid}")
    school  = School.create!(name: "Esc IT #{uid}", code: "EIT#{uid}", faculty: faculty)
    plan    = StudyPlan.create!(code: "SPIT#{uid}", name: "Plan IT #{uid}", school: school)
    adm     = AdmissionType.create!(name: "Adm IT #{uid}", code: "AIT#{uid}")
    user    = User.create!(ci: "IT#{uid}#{rand(10**8)}", email: "it#{uid}@test.com",
                           first_name: "Int", last_name: "Egracion", password: "password123", updated_password: true)
    student = Student.create!(user: user)
    Grade.create!(student: student, study_plan: plan, admission_type: adm,
                  graduate_status: graduate_status, current_permanence_status: :regular)
  end
end
