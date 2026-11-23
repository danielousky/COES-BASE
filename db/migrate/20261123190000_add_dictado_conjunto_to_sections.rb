# Las secciones que se dictan juntas: el mismo profesor, a la misma hora y en la misma aula, aunque sean de
# asignaturas distintas (en 2026-02, Canto Coral I, III, IV y V A1, martes y jueves de 12:30 a 2:30 pm). Llevan el
# mismo número en dictado_conjunto, y la grilla del horario no avisa el choque del profesor entre ellas (23-nov).
# Sin datos: la marcan los asistentes con «Se dictan juntas» cuando la grilla les avisa el choque.
class AddDictadoConjuntoToSections < ActiveRecord::Migration[7.0]
  def change
    add_column :sections, :dictado_conjunto, :bigint
    add_index :sections, :dictado_conjunto
  end
end
