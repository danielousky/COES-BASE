class AsignaturaPeriodoInscripcionUnicaValidator < ActiveModel::Validator
  def validate(record)
    if unica_inscripcion_asignatura_periodo(record)
      record.errors.add 'La asignatura', 'ya fue inscrita para el período seleccionado.'
    end
  end

  private
    def unica_inscripcion_asignatura_periodo(record)
      periodo_id = record.periodo.id
      asignatura_id = record.asignatura.id
      record.grado.inscripciones.joins(:asignatura).del_periodo(periodo_id).where('asignaturas.id': asignatura_id).any?
      
    end
end