class SeedPremioMeritoGeneralSetup < ActiveRecord::Migration[7.0]
  # Los mínimos del Premio al Mérito Académico, editables desde el admin. Idempotente: no pisa un
  # valor que un admin ya haya ajustado.
  DESCRIPCIONES = {
    creditos_semestre: 'Premio al Mérito: créditos mínimos inscritos en cada semestre del año (carreras semestrales).',
    creditos_anual: 'Premio al Mérito: créditos mínimos inscritos en el año (carreras anuales).',
    promedio_mayor_a: 'Premio al Mérito: el promedio simple del año tiene que ser mayor a este valor.'
  }.freeze

  def up
    School::PremioMerito::MINIMOS.each do |nombre, (clave, por_defecto)|
      GeneralSetup.find_or_create_by!(clave: clave) do |gs|
        gs.valor = por_defecto.to_s
        gs.description = DESCRIPCIONES.fetch(nombre)
      end
    end
  end

  def down
    GeneralSetup.where(clave: School::PremioMerito::MINIMOS.values.map(&:first)).destroy_all
  end
end
