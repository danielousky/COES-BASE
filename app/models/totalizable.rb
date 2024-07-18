module Totalizable

  def total_academic_records
    academic_records_count
  end

  def total_sc
    academic_records.sin_calificar.count
  end

  def total_aprobados
    academic_records.not_perdida_por_inasistencia.aprobado.count
  end

  def total_aplazados
    academic_records.not_perdida_por_inasistencia.aplazado.count
  end

  def total_retirados
    academic_records.retirado.count
  end

  def total_pi
    academic_records.perdida_por_inasistencia.count
  end

  def label_numbery_total
    aux = ApplicationController.helpers.label_status('bg-info', total_academic_records)
    aux += ApplicationController.helpers.label_status('bg-secondary', total_sc)
    aux += ApplicationController.helpers.label_status('bg-success', total_aprobados)
    aux += ApplicationController.helpers.label_status('bg-danger', total_aplazados)
    aux += ApplicationController.helpers.label_status('bg-secondary', total_retirados)
    aux += ApplicationController.helpers.label_status('bg-danger', total_pi)  
  end
end
