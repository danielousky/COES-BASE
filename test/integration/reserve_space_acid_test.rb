require "test_helper"

# Pruebas de atomicidad ACID para EnrollAcademicProcessesController#reserve_space
# (app/controllers/enroll_academic_processes_controller.rb:72).
#
# La acción es la operación más sensible del módulo de inscripción: libera el
# cupo previo del estudiante y reserva el cupo nuevo en la sección elegida.
# El bloque ActiveRecord::Base.transaction garantiza que:
#
#   - Si las 4 validaciones de negocio fallan (solapamiento, créditos,
#     asignaturas, capacidad), todo se revierte y el estudiante mantiene su
#     reserva anterior intacta.
#   - Si todo pasa, el AcademicRecord previo queda destruido y el nuevo
#     persistido.
#
# Estos tests respaldan la afirmación del informe de auditoría sobre
# transacciones ACID en el flujo de inscripción (mayo 2026).
class ReserveSpaceAcidTest < ActionDispatch::IntegrationTest
  # Las fixtures globales (admins/env_auths) presentan FK violations al
  # cargarse en un test de integración. Como ninguna fixture aplica al flujo
  # bajo prueba, vaciamos la lista para esta clase (manteniendo el wrapping
  # transaccional intacto) y construimos toda la data en setup.
  self.fixture_table_names = []

  setup do
    @uid       = SecureRandom.hex(4)
    # SubjectType valida format \A[a-z]+\z; necesitamos un sufijo sólo letras.
    @uid_alpha = (("a".."z").to_a.sample(8)).join

    # Jerarquía académica
    @faculty = Faculty.create!(
      name:           "Facultad RS #{@uid}",
      code:           "FRS#{@uid}",
      contact_email:  "frs#{@uid}@test.com",
      coes_boss_name: "Jefe RS #{@uid}"
    )
    @school = School.create!(name: "Escuela RS #{@uid}", code: "ERS#{@uid}", faculty: @faculty)
    @study_plan = StudyPlan.create!(code: "SPRS#{@uid}", name: "Plan RS #{@uid}", school: @school)
    @admission_type = AdmissionType.create!(name: "Adm RS #{@uid}", code: "ARS#{@uid}")

    @period_type = PeriodType.create!(code: "U#{@uid}", name: "Único #{@uid}")
    @period      = Period.create!(year: 2025, period_type: @period_type)

    # Proceso académico con cupos altos -> happy path no se cae por límites.
    # En la prueba de rollback se sobrescribe con max_credits = 0.
    @academic_process = AcademicProcess.create!(
      school: @school, period: @period,
      max_credits: 24, max_subjects: 6
    )

    # Asignatura completa (Area, Departament, SubjectType)
    @subject_type = SubjectType.create!(code: "OB#{@uid_alpha}", name: "Obligatoria #{@uid}")
    @area         = Area.create!(name: "Area RS #{@uid}", school: @school)
    @departament  = Departament.create!(name: "Dpto RS #{@uid}", school: @school)
    @departament.areas << @area  # SameDepartamentAreaOnSubjectValidator
    @subject = Subject.create!(
      code:               "MAT#{@uid}",
      name:               "Matemática #{@uid}",
      ordinal:            1,
      subject_type:       @subject_type,
      qualification_type: :numerica,
      unit_credits:       5,
      area:               @area,
      departament:        @departament,
      school:             @school
    )

    # Curso + Sección con capacidad amplia y sin horario (overlapped? = false).
    @course  = Course.create!(subject: @subject, academic_process: @academic_process, offer_as_pci: false)
    @section = Section.create!(
      course:    @course,
      code:      "S1",
      capacity:  30,
      modality:  :nota_final,
      qualified: false
    )

    # Usuario autenticable + Estudiante + Grade
    @user = User.create!(
      ci:               "RS#{@uid}#{rand(10**6)}",
      email:            "rs#{@uid}@test.com",
      first_name:       "Estu",
      last_name:        "Diante",
      password:         "password123",
      updated_password: true
    )
    @student = Student.create!(user: @user)
    @grade   = Grade.create!(
      student: @student, study_plan: @study_plan, admission_type: @admission_type,
      current_permanence_status: :regular
    )

    sign_in @user
  end

  # ---------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------

  test "happy path: reserva crea EnrollAcademicProcess + AcademicRecord" do
    assert_difference -> { EnrollAcademicProcess.count } => 1,
                      -> { AcademicRecord.count }       => 1 do
      post reserve_space_enroll_academic_processes_path(format: :json), params: {
        course_id:           @course.id,
        section_id:          @section.id,
        grade_id:            @grade.id,
        academic_process_id: @academic_process.id
      }
    end

    body = JSON.parse(response.body)
    assert_equal "success", body["status"], "Respuesta JSON: #{body.inspect}"

    eap = EnrollAcademicProcess.find_by(grade: @grade, academic_process: @academic_process)
    assert_not_nil eap
    assert eap.academic_records.where(section: @section).exists?
  end

  # ---------------------------------------------------------------------
  # Rollback por exceso de créditos
  # ---------------------------------------------------------------------

  test "rollback: exceso de créditos no crea ningún registro" do
    # max_credits = 0 hace que credits_attemp (5) > limit (0) -> ActiveRecord::Rollback
    @academic_process.update!(max_credits: 0)

    assert_no_difference [-> { EnrollAcademicProcess.count }, -> { AcademicRecord.count }] do
      post reserve_space_enroll_academic_processes_path(format: :json), params: {
        course_id:           @course.id,
        section_id:          @section.id,
        grade_id:            @grade.id,
        academic_process_id: @academic_process.id
      }
    end

    body = JSON.parse(response.body)
    assert_equal "error", body["status"]
    assert_match(/créditos/i, body["data"])

    assert_nil EnrollAcademicProcess.find_by(grade: @grade, academic_process: @academic_process),
      "No debe persistir EnrollAcademicProcess cuando la transacción se revierte (atomicidad)"
  end

  # ---------------------------------------------------------------------
  # Rollback preserva la reserva previa del estudiante
  # ---------------------------------------------------------------------

  test "rollback preserva el AcademicRecord previo en la misma asignatura" do
    # Reserva previa válida en otra sección del mismo curso.
    section_previa = Section.create!(
      course: @course, code: "S0", capacity: 30, modality: :nota_final, qualified: false
    )
    eap_previo = EnrollAcademicProcess.create!(
      grade: @grade, academic_process: @academic_process,
      enroll_status: :reservado, permanence_status: :regular
    )
    ar_previo = AcademicRecord.create!(
      section: section_previa, enroll_academic_process: eap_previo, status: :sin_calificar
    )

    # Forzar fallo en el intento de reservar la nueva sección.
    @academic_process.update!(max_credits: 0)

    # La transacción debe destruir el AR previo y luego revertir TODO al fallar
    # la validación de créditos. Resultado neto: ningún cambio.
    assert_no_difference [-> { AcademicRecord.count }] do
      post reserve_space_enroll_academic_processes_path(format: :json), params: {
        course_id:           @course.id,
        section_id:          @section.id,
        grade_id:            @grade.id,
        academic_process_id: @academic_process.id
      }
    end

    assert AcademicRecord.exists?(ar_previo.id),
      "El AcademicRecord previo del estudiante NO debe perderse cuando la nueva " \
      "reserva es rechazada (consistencia)"
  end

  # ---------------------------------------------------------------------
  # Liberar cupo: sin section_id se libera el AR existente y no se crea otro
  # ---------------------------------------------------------------------

  test "liberar cupo (sin section_id) elimina el AR existente sin crear nada" do
    eap = EnrollAcademicProcess.create!(
      grade: @grade, academic_process: @academic_process,
      enroll_status: :reservado, permanence_status: :regular
    )
    AcademicRecord.create!(section: @section, enroll_academic_process: eap, status: :sin_calificar)

    assert_difference -> { AcademicRecord.count } => -1 do
      post reserve_space_enroll_academic_processes_path(format: :json), params: {
        course_id:           @course.id,
        grade_id:            @grade.id,
        academic_process_id: @academic_process.id
        # sin section_id -> sólo libera
      }
    end

    body = JSON.parse(response.body)
    assert_equal "success", body["status"]
  end
end
