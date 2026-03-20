class AsignaturaAprobadaUnicaValidator < ActiveModel::Validator
  def validate(record)
    aux = asignatura_aprobada(record)

    if aux and (record.aprobado? or (record.aplazado? and record.periodo.es_mayor_que? aux.periodo))
      record.errors.add 'La asignatura', "ya fue aprobada en el período #{aux.periodo.id}"
    end
  end

  private
    def asignatura_aprobada(record)
      # query optimo o mejor (opinón personal)
      # record.estudiante.inscripcionsecciones.aprobado.joins(:grado).joins(:asignatura).where("grados.estudiante_id = #{record.estudiante_id} and grados.escuela_id = #{record.escuela_id} and asignaturas.id = #{record.asignatura.id}")

      record.grado.inscripciones.joins(:asignatura).aprobadas.where('asignaturas.id': record.asignatura.id).first
    end
end