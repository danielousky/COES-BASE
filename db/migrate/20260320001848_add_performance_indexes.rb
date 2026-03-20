class AddPerformanceIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    # academic_records: 40+ scopes filtran por status
    add_index :academic_records, [:status, :enroll_academic_process_id],
              name: :idx_academic_records_status_eap, algorithm: :concurrently
    add_index :academic_records, [:status, :section_id],
              name: :idx_academic_records_status_section, algorithm: :concurrently

    # enroll_academic_processes: scopes de inscripción por status y proceso
    add_index :enroll_academic_processes, [:academic_process_id, :enroll_status, :permanence_status],
              name: :idx_eap_process_statuses, algorithm: :concurrently
    add_index :enroll_academic_processes, [:grade_id, :academic_process_id],
              name: :idx_eap_grade_process, algorithm: :concurrently

    # subjects: cálculo de niveles y oferta académica
    add_index :subjects, [:ordinal, :active, :area_id],
              name: :idx_subjects_ordinal_active_area, algorithm: :concurrently

    # grades: filtro de citas de inscripción
    add_index :grades, :appointment_time,
              name: :idx_grades_appointment_time, algorithm: :concurrently

    # sections: dashboard de secciones calificadas
    add_index :sections, [:qualified, :course_id],
              name: :idx_sections_qualified_course, algorithm: :concurrently
  end
end
