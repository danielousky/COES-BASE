# Los contadores de la Programación (academic_processes/_index_programation): las mismas consultas sirven para
# dibujarlos y para ponerlos al día por Turbo Stream al crear o borrar una sección (ProgramacionSeccionesController).
module ProgramacionHelper
  # Las secciones del área en el período, de las asignaturas del departamento elegido.
  def secciones_del_area(area, proceso_id, dpto_id)
    area.sections.joins(:departament).where('courses.academic_process_id': proceso_id, 'departaments.id': dpto_id).count
  end

  # Las secciones del área en el período con esa tipología, de cualquier departamento (así las contaba la pestaña).
  def secciones_de_la_tipologia(area, proceso_id, codigo)
    area.sections.where('courses.academic_process_id': proceso_id).joins(:subject_type).where('subject_types.code': codigo).count
  end
end
