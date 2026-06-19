require "test_helper"

# Pruebas de atomicidad ACID para Student.import (app/models/student.rb:521).
#
# El método importa una fila de Excel/CSV y crea/actualiza User + Student +
# Grade (y, si row[6] está presente, Period + AcademicProcess) dentro de un
# bloque ActiveRecord::Base.transaction. El contrato auditado es:
#
#   - Happy path: todos los registros se persisten.
#   - Cualquier fallo intermedio revierte TODOS los inserts: ningún
#     User/Student/Grade/Period/AcademicProcess queda huérfano (atomicidad +
#     consistencia).
#
# Estos tests respaldan la afirmación del informe de auditoría sobre el uso de
# transacciones ACID en el módulo de registro de usuarios (mayo 2026).
class StudentImportAcidTest < ActiveSupport::TestCase

  def setup
    @uid = SecureRandom.hex(4)

    @faculty = Faculty.create!(
      name:           "Facultad ACID #{@uid}",
      code:           "FAC#{@uid}",
      contact_email:  "fac#{@uid}@test.com",
      coes_boss_name: "Jefe ACID #{@uid}"
    )
    @school     = School.create!(name: "Escuela ACID #{@uid}", code: "EA#{@uid}", faculty: @faculty)
    @study_plan = StudyPlan.create!(code: "SPACID#{@uid}", name: "Plan ACID #{@uid}", school: @school)
    @admission_type = AdmissionType.create!(name: "Ord ACID #{@uid}", code: "ORDA#{@uid}")

    # CI único por test para evitar colisiones en paralelo.
    @ci = "ACI#{@uid}#{rand(10**8)}"
    @row = [@ci, "acid#{@uid}@test.com", "Juan", "Pérez", "M", "555-0000", nil, nil, 2024]
    @fields = {
      study_plan_id:     @study_plan.id,
      admission_type_id: @admission_type.id,
      console:           true
    }
  end

  # ---------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------

  test "happy path: persiste User + Student + Grade en una transacción" do
    total_newed = total_updated = no_registred = nil

    assert_difference -> { User.count }    => 1,
                      -> { Student.count } => 1,
                      -> { Grade.count }   => 1 do
      total_newed, total_updated, no_registred = Student.import(@row, @fields)
    end

    assert_equal 1, total_newed,    "Debe contar 1 grade nuevo"
    assert_equal 0, total_updated,  "No debe contar como actualización"
    assert_nil no_registred,        "no_registred debe quedar nulo en éxito"

    user = User.find_by(ci: @ci)
    assert_not_nil user,                                      "User debe persistir"
    assert_not_nil user.student,                              "Student debe persistir"
    assert user.student.grades.exists?(study_plan_id: @study_plan.id),
      "Grade debe persistir asociado al StudyPlan"
  end

  # ---------------------------------------------------------------------
  # Rollback: validación falla en grade
  # ---------------------------------------------------------------------

  test "rollback: study_plan_id inexistente revierte User y Student" do
    # Un study_plan_id inexistente hace que la asociación belongs_to :study_plan
    # quede en nil, la validación presence falla en Grade y, por autosave en
    # estudiante.save! (vía accepts_nested_attributes_for :grades), la
    # transacción se revierte completa.
    bogus_id = StudyPlan.maximum(:id).to_i + 9_999
    @fields[:study_plan_id] = bogus_id

    assert_no_difference [-> { User.count }, -> { Student.count }, -> { Grade.count }] do
      _newed, _updated, no_registred = Student.import(@row, @fields)
      assert_equal @row, no_registred,
        "La fila debe reportarse como no registrada cuando la transacción falla"
    end

    assert_nil User.find_by(ci: @ci),
      "El usuario NO debe quedar huérfano cuando un paso intermedio falla (atomicidad)"
  end

  # ---------------------------------------------------------------------
  # Rollback: excepción dentro del bloque transaction
  # ---------------------------------------------------------------------

  test "rollback: row[6] con PeriodType inexistente revierte todo el alta" do
    # row[6] = "2025-XX0" -> PeriodType.find_by_code('XX') devuelve nil ->
    # period_type.id explota (NoMethodError) DENTRO de la transacción. El
    # rescue StandardError marca la fila como no registrada y la BD revierte
    # User/Student/Grade que ya se habían tocado antes del fallo.
    @row[6] = "2025-XX0"

    assert_no_difference [-> { User.count }, -> { Student.count },
                          -> { Grade.count }, -> { Period.count }] do
      _newed, _updated, no_registred = Student.import(@row, @fields)
      assert_equal @row, no_registred
    end

    assert_nil User.find_by(ci: @ci),
      "Excepción dentro de transaction debe revertir creación de User"
  end

  # ---------------------------------------------------------------------
  # Rollback: no contamina datos previos
  # ---------------------------------------------------------------------

  test "rollback no afecta a un User pre-existente con el mismo CI" do
    # User pre-existente con el CI: el método hace find_or_initialize_by, así
    # que opera sobre el mismo registro. Si la transacción falla, los datos
    # del User previo deben quedar intactos.
    pre_user = User.create!(
      ci:               @ci,
      email:            "pre#{@uid}@test.com",
      first_name:       "Original",
      last_name:        "Apellido",
      password:         "password123",
      updated_password: true
    )
    Student.create!(user: pre_user)

    # Forzar fallo con study_plan_id inexistente
    @fields[:study_plan_id] = StudyPlan.maximum(:id).to_i + 9_999
    @row[2] = "ModificadoEnImport"

    assert_no_difference [-> { User.count }, -> { Student.count }] do
      Student.import(@row, @fields)
    end

    pre_user.reload
    # User normaliza first_name a mayúsculas en el callback before_save.
    assert_equal "Original".upcase, pre_user.first_name,
      "Los datos del User pre-existente NO deben quedar parcialmente modificados " \
      "tras un rollback (consistencia)"
  end
end
