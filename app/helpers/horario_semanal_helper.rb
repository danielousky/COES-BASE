# La grilla semanal del horario de una sección (23-nov, como en FAU): la usan el formulario de la sección del admin
# (timetables/_horario_semanal) y el panel de la Programación (programacion/secciones/_panel). Dentro de rails_admin
# se llama con ApplicationController.helpers, como los demás helpers de la Programación.
module HorarioSemanalHelper
  # Los atributos del contenedor: el controlador «horario-semanal» con los bloques de la sección (también los que no
  # se guardaron, si el servidor rechazó el formulario), el id de su horario si ya existe y el prefijo de los campos.
  # Con «capas» (el panel de la Programación), lo que la grilla muestra alrededor (CapasDelHorario) y dónde pedir las
  # clases de otro profesor.
  def horario_semanal_atributos(seccion, prefijo, clase: nil, capas: nil, url_capas: nil)
    horario = seccion.timetable
    bloques = Timeblock.para_grilla(horario ? horario.timeblocks.to_a : [], borrados: horario&.marked_for_destruction?)
    {class: ['horario-semanal', clase].compact.join(' '), style: "--hs-horas: #{Timeblock::HORA_MAXIMA - Timeblock::HORA_MINIMA}",
     data: {controller: 'horario-semanal', action: 'keydown@window->horario-semanal#tecla', horario_semanal_prefijo_value: prefijo,
            horario_semanal_horario_value: (horario.id.to_s if horario&.persisted?),
            horario_semanal_bloques_value: bloques.to_json,
            horario_semanal_capas_value: capas&.to_json, horario_semanal_ocupacion_value: url_capas}.compact}
  end

  # Lo que el servidor dijo del horario al rechazarlo: «Lunes de 7:00 pm a 7:15 pm: dura menos de 30 minutos».
  # Sin el nombre del campo, que en los anidados sale «Timetable timeblocks end time».
  def horario_semanal_errores(seccion)
    seccion.errors.select { |e| e.attribute.to_s.start_with?('timetable') }.map(&:message).uniq
  end
end
