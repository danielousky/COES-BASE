# == Schema Information
#
# Table name: enrollment_days
#
#  id                    :bigint           not null, primary key
#  by_before_process     :boolean          default(TRUE), not null
#  max_grades            :integer
#  slot_duration_minutes :integer
#  start                 :datetime
#  total_duration_hours  :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  academic_process_id   :bigint           not null
#
require "test_helper"

# Pruebas para EnrollmentDay, enfocadas en los métodos de cálculo de citas horarias:
#   - total_timeslots: cuántas franjas horarias caben en la jornada
#   - grades_by_timeslot: cuántos grados se asignan por franja
#   - mod_to_grades: el residuo de grados que no caben exactamente en franjas
#
# Estos métodos controlan la distribución de citas horarias a estudiantes y
# son críticos para el correcto funcionamiento de la jornada de inscripción.
class EnrollmentDayTest < ActiveSupport::TestCase

  # -----------------------------------------------------------------------
  # Helpers de construcción en memoria para evitar dependencias de fixtures
  # complejas. Solo se persiste cuando el test lo requiera explícitamente.
  # -----------------------------------------------------------------------

  def build_enrollment_day(total_duration_hours:, slot_duration_minutes:, max_grades:)
    EnrollmentDay.new(
      total_duration_hours:  total_duration_hours,
      slot_duration_minutes: slot_duration_minutes,
      max_grades:            max_grades,
      # start y academic_process_id son requeridos por validaciones, pero
      # no afectan la lógica de cálculo que estamos probando, así que se
      # dejan sin persistir usando instancias en memoria.
      start:                 Time.current + 1.day,
      academic_process_id:   0  # valor placeholder para tests unitarios
    )
  end

  # -----------------------------------------------------------------------
  # total_timeslots
  # -----------------------------------------------------------------------

  test "total_timeslots devuelve 8 para jornada de 8 horas con franjas de 60 minutos" do
    jornada = build_enrollment_day(total_duration_hours: 8, slot_duration_minutes: 60, max_grades: 100)

    assert_equal 8, jornada.total_timeslots
  end

  test "total_timeslots devuelve 16 para jornada de 8 horas con franjas de 30 minutos" do
    jornada = build_enrollment_day(total_duration_hours: 8, slot_duration_minutes: 30, max_grades: 100)

    assert_equal 16, jornada.total_timeslots
  end

  test "total_timeslots devuelve 0 cuando slot_duration_minutes es 0 (evita división por cero)" do
    jornada = build_enrollment_day(total_duration_hours: 8, slot_duration_minutes: 0, max_grades: 100)

    assert_equal 0, jornada.total_timeslots
  end

  test "total_timeslots redondea hacia abajo cuando la división no es exacta" do
    # 5 horas / 45 minutos = 6.67 franjas -> trunca a 6
    jornada = build_enrollment_day(total_duration_hours: 5, slot_duration_minutes: 45, max_grades: 50)

    assert_equal 6, jornada.total_timeslots
  end

  test "total_timeslots devuelve 0 cuando total_duration_hours es 0" do
    jornada = build_enrollment_day(total_duration_hours: 0, slot_duration_minutes: 60, max_grades: 100)

    assert_equal 0, jornada.total_timeslots
  end

  # -----------------------------------------------------------------------
  # grades_by_timeslot
  # -----------------------------------------------------------------------

  test "grades_by_timeslot devuelve 55 para 443 grados en 8 franjas de 60 min (8 horas)" do
    # 443 / 8 = 55.375 -> trunca a 55
    jornada = build_enrollment_day(total_duration_hours: 8, slot_duration_minutes: 60, max_grades: 443)

    assert_equal 55, jornada.grades_by_timeslot
  end

  test "grades_by_timeslot devuelve max_grades cuando hay mas franjas que grados" do
    # Si total_timeslots (16) > max_grades (10), se devuelve max_grades directamente
    jornada = build_enrollment_day(total_duration_hours: 8, slot_duration_minutes: 30, max_grades: 10)

    # total_timeslots = 16, que es > 10
    assert_equal 10, jornada.grades_by_timeslot
  end

  test "grades_by_timeslot devuelve 0 cuando total_timeslots es 0" do
    jornada = build_enrollment_day(total_duration_hours: 8, slot_duration_minutes: 0, max_grades: 100)

    assert_equal 0, jornada.grades_by_timeslot
  end

  test "grades_by_timeslot distribuye uniformemente cuando la division es exacta" do
    # 120 grados / 4 franjas = 30 exactos
    jornada = build_enrollment_day(total_duration_hours: 4, slot_duration_minutes: 60, max_grades: 120)

    assert_equal 30, jornada.grades_by_timeslot
  end

  # -----------------------------------------------------------------------
  # mod_to_grades
  # -----------------------------------------------------------------------

  test "mod_to_grades devuelve 3 para 443 grados en 8 franjas (443 mod 8 = 3)" do
    jornada = build_enrollment_day(total_duration_hours: 8, slot_duration_minutes: 60, max_grades: 443)

    assert_equal 3, jornada.mod_to_grades
  end

  test "mod_to_grades devuelve 0 cuando la distribucion es exacta" do
    # 120 grados / 4 franjas = 30 exactos, sin residuo
    jornada = build_enrollment_day(total_duration_hours: 4, slot_duration_minutes: 60, max_grades: 120)

    assert_equal 0, jornada.mod_to_grades
  end

  test "mod_to_grades devuelve 0 cuando total_timeslots es 0 (evita mod por cero)" do
    jornada = build_enrollment_day(total_duration_hours: 8, slot_duration_minutes: 0, max_grades: 100)

    assert_equal 0, jornada.mod_to_grades
  end

  test "mod_to_grades devuelve el residuo correcto para division no exacta" do
    # 100 grados / 3 franjas (jornada 3 horas, franjas 60 min) = 33 con residuo 1
    jornada = build_enrollment_day(total_duration_hours: 3, slot_duration_minutes: 60, max_grades: 100)

    assert_equal 1, jornada.mod_to_grades
  end

  # -----------------------------------------------------------------------
  # Consistencia de los tres métodos entre sí
  # (verifica que la distribución cubre todos los grados esperados)
  # -----------------------------------------------------------------------

  test "la distribucion completa de slots cubre todos los grados maximos" do
    # grades_by_timeslot * total_timeslots + mod_to_grades debe ser == max_grades
    jornada = build_enrollment_day(total_duration_hours: 8, slot_duration_minutes: 60, max_grades: 443)

    grados_en_franjas_completas = jornada.grades_by_timeslot * jornada.total_timeslots
    residuo                     = jornada.mod_to_grades

    assert_equal jornada.max_grades, grados_en_franjas_completas + residuo,
      "grades_by_timeslot * total_timeslots + mod_to_grades debe sumar max_grades"
  end

end
