# El aula vive en el bloque (Daniel, 20-nov-2026). sections.classroom es de antes de jun-2025 y la app ya no la lee,
# así que los bloques sin aula cuya sección sí tiene reciben la de la sección. En producción eran 2, de 2026-01.
class AulaDeLaSeccionASusBloques < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL
      UPDATE timeblocks
         SET classroom = TRIM(sections.classroom), updated_at = NOW()
        FROM timetables, sections
       WHERE timeblocks.timetable_id = timetables.id
         AND timetables.section_id = sections.id
         AND COALESCE(TRIM(timeblocks.classroom), '') = ''
         AND COALESCE(TRIM(sections.classroom), '') <> ''
    SQL
  end

  # No se deshace: los valores de antes quedan en el respaldo que se saca justo antes de desplegar.
  def down; end
end
