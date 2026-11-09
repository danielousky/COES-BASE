class SeedPremioMeritoPorCarrera < ActiveRecord::Migration[7.0]
  # Con SI el Premio al Mérito es por la carrera y por año de la carrera (ODON); con NO, por el año (FHE, FAU).
  # Idempotente: no pisa lo que un admin ya haya puesto.
  CLAVE = 'PREMIO_MERITO_POR_CARRERA'.freeze

  def up
    GeneralSetup.find_or_create_by!(clave: CLAVE) do |gs|
      gs.valor = 'NO'
      gs.description = 'Premio al Mérito: SI = por la carrera (eficiencia 1, promedio simple y ponderado de toda la ' \
                       'carrera; los 10 primeros en la General y en cada año). NO = por el año (carga completa y ' \
                       'promedio del año).'
    end
  end

  def down
    GeneralSetup.where(clave: CLAVE).destroy_all
  end
end
