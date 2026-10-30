class AddFirstCareerToAdmissionTypes < ActiveRecord::Migration[7.0]
  # Premio al Mérito Académico: solo cuentan los estudiantes de primera carrera. Arranca en «sí» para
  # las formas de ingreso por primera vez de la UCV (códigos 0101-0199: OPSU, prueba interna, convenios…)
  # y en «no» para equivalencias, simultáneos, egresados, traslados de otra universidad y cambios.
  # Cada facultad lo corrige en el admin, en la forma de ingreso.
  def up
    add_column :admission_types, :first_career, :boolean, default: false, null: false
    execute <<~SQL
      UPDATE admission_types SET first_career = true
      WHERE code ~ '^[0-9]+$' AND code::integer BETWEEN 101 AND 199
    SQL
  end

  def down
    remove_column :admission_types, :first_career
  end
end
