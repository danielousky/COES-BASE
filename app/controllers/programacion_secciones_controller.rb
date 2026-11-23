# La sección en la Programación (FHE 23-nov; nació en FAU el 17-nov): se crea, se duplica, se corrige y se borra en la
# misma fila de la asignatura, sin salir de la página ni recargarla. Reemplaza al modal que copiaba el formulario de
# rails_admin (en FAU, Daniel: «era poco mantenible: cuando modificaba uno, tenía que modificar el otro»), que además
# mandaba el profesor de cada bloque como el de la sección.
#
#   [+] o una sección   ─► GET con Turbo Stream ─► el panel, en una fila debajo de la asignatura
#   Crear / Guardar     ─► POST o PATCH         ─► las secciones de esa fila, ya sin el panel
#                                                  └─ si no se guardó, el panel otra vez, con el motivo
#   × o 🗑              ─► DELETE               ─► las secciones de esa fila
#   otro profesor       ─► GET en JSON          ─► sus otras clases, para la grilla (ocupacion)
#
# Alrededor del horario, la grilla muestra las otras clases del profesor, las otras secciones y el semestre
# (CapasDelHorario). Si el cambio trae un choque nuevo del profesor, no se guarda hasta que se elija qué hacer
# (ChoqueDelProfesor): el admin no lo revisa.
#
# Al crear o borrar también se ponen al día los contadores de la página (el total, el departamento, el área y la
# tipología). Lo que se guarda es lo mismo que en el admin (también el horario, con la misma grilla), así que las
# validaciones del modelo son las mismas en los dos lados.
#
# En FAU es Programacion::SeccionesController. En FHE, Programacion es el modelo de la tabla vieja «programaciones»,
# así que no puede ser también un módulo: aquí va sin módulo, con las mismas rutas y los mismos nombres de ruta.
class ProgramacionSeccionesController < ApplicationController
  before_action :require_admin
  before_action :set_seccion, only: %i[edit update destroy]
  before_action :set_curso, except: :profesores
  before_action :autorizar_escuela, except: :profesores
  before_action :autorizar_crear, only: %i[new create]
  before_action :autorizar_editar, only: %i[edit update]
  before_action :autorizar_borrar, only: %i[destroy eliminar_todas]
  before_action :autorizar_buscar, only: %i[profesores ocupacion]

  # Nueva, o duplicada de otra («desde»): el mismo cupo, profesor y horario, con el código que sigue.
  def new
    @origen = @curso.sections.includes(timetable: :timeblocks).find_by(id: params[:desde])
    @seccion = Section.new(course: @curso, capacity: @origen&.capacity || cupo_sugerido, teacher_id: @origen&.teacher_id,
                           code: Section.siguiente_codigo(@curso.sections.pluck(:code), codigos_de_la_vez_anterior, codigo_frecuente))
    copiar_horario if @origen&.timetable
    abrir_panel
  end

  def edit
    abrir_panel
  end

  def create
    @seccion = Section.new(seccion_params.merge(course: @curso, revisar_choques: true))
    guardar
  end

  def update
    @seccion.assign_attributes(seccion_params.merge(revisar_choques: true))
    guardar
  end

  def destroy
    return no_se_borra("La #{@seccion.code} tiene inscritos: elimine las inscripciones primero.") if @seccion.academic_records.exists?

    @seccion.destroy!
    borradas("Se eliminó la sección #{@seccion.code}.")
  end

  def eliminar_todas
    return no_se_borra('Hay secciones con inscritos: elimine las inscripciones primero.') if @curso.academic_records.exists?

    total = @curso.sections.destroy_all.size
    borradas("Se #{total == 1 ? 'eliminó 1 sección' : "eliminaron #{total} secciones"}.")
  end

  # El buscador del profesor: mientras se escribe, por nombre, apellido o cédula, sin importar los acentos.
  def profesores
    palabras = params[:q].to_s.split.first(4)
    return render(json: []) if palabras.join.length < 2

    texto = "translate(lower(concat_ws(' ', users.first_name, users.last_name, users.ci)), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunaeiouun')"
    encontrados = palabras.inject(Teacher.joins(:user)) do |consulta, palabra|
      consulta.where("#{texto} LIKE ?", "%#{Teacher.sanitize_sql_like(I18n.transliterate(palabra).downcase)}%")
    end
    render json: encontrados.order('users.last_name', 'users.first_name').limit(12).includes(:user)
                            .map { |t| {id: t.id, nombre: t.user.reverse_name, ci: t.user.ci} }
  end

  # Las otras clases del profesor que se acaba de elegir en el buscador, para la capa de la grilla.
  def ocupacion
    seccion = @curso.sections.find_by(id: params[:seccion_id]) || Section.new(course: @curso)
    render json: {profesor: CapasDelHorario.new(seccion, profesor_id: params[:profesor_id]).profesor}
  end

  private

  def abrir_panel
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove_all('.programacion-panel'),
          turbo_stream.after("programacion_asignatura_#{@curso.subject_id}", partial: 'programacion/secciones/panel', locals: panel)
        ]
      end
      format.html { redirect_to "/admin/academic_process/#{@curso.academic_process_id}/programation" }
    end
  end

  # Al crear, también los contadores. El aviso dice qué pasó, como al borrar (Daniel, 23-nov: al crear no había).
  def guardar
    nueva = @seccion.new_record?
    cambio = @seccion.changed_for_autosave? || @seccion.cambia_el_dictado_conjunto?
    if @seccion.save
      render turbo_stream: [
        turbo_stream.remove("panel_curso_#{@curso.id}"),
        secciones_de_la_fila(resaltar: @seccion.id),
        *(nueva ? contadores : []),
        aviso(aviso_al_guardar(nueva, cambio), 'success')
      ]
    else
      render turbo_stream: turbo_stream.replace("panel_curso_#{@curso.id}", partial: 'programacion/secciones/panel', locals: panel),
             status: :unprocessable_entity
    end
  end

  # Si era nueva o si cambió algo se mira antes de guardar; el código, después (el guardado pone «03» por «3»).
  def aviso_al_guardar(nueva, cambio)
    return "Se creó la sección #{@seccion.code}." if nueva
    return "La sección #{@seccion.code} no tenía cambios." unless cambio

    "Se guardaron los cambios de la sección #{@seccion.code}."
  end

  # Si el panel abierto era de la que se borró, se cierra también.
  def borradas(mensaje)
    render turbo_stream: [
      turbo_stream.remove("panel_curso_#{@curso.id}"),
      secciones_de_la_fila,
      *contadores,
      aviso(mensaje, 'success')
    ]
  end

  def no_se_borra(mensaje)
    render turbo_stream: [secciones_de_la_fila, aviso(mensaje, 'error')], status: :unprocessable_entity
  end

  def secciones_de_la_fila(resaltar: nil)
    turbo_stream.replace("secciones_curso_#{@curso.id}", partial: 'programacion/secciones/secciones',
                         locals: {curso: @curso, resaltar: resaltar})
  end

  # Los mismos contadores de la página (rails_admin/main/programation y _index_programation), con las mismas
  # consultas (ProgramacionHelper): el total del período, el del departamento en su selector, el del área y el de la
  # tipología de la asignatura.
  def contadores
    materia = @curso.subject
    proceso = @curso.academic_process
    dpto = materia.departament
    ayuda = helpers
    [
      turbo_stream.update('programacion_total_secciones', proceso.sections.count.to_s),
      (turbo_stream.update("programacion_conteo_dpto_#{dpto.id}", dpto.total_section_by_process_and_name(proceso.id)) if dpto),
      turbo_stream.update("programacion_conteo_area_#{materia.area_id}",
                          ayuda.total_sections_stiky(ayuda.secciones_del_area(materia.area, proceso.id, dpto&.id))),
      turbo_stream.update("programacion_conteo_area_#{materia.area_id}_#{materia.subject_type&.code}",
                          ayuda.total_sections_stiky(ayuda.secciones_de_la_tipologia(materia.area, proceso.id, materia.subject_type&.code)))
    ].compact
  end

  # Un aviso de toastr, que llega por Turbo Stream (el controlador «aviso» lo muestra y se borra).
  def aviso(mensaje, tipo)
    turbo_stream.append_all('body', helpers.tag.div(data: {controller: 'aviso', aviso_tipo_value: tipo, aviso_texto_value: mensaje}))
  end

  # Con lo que la grilla muestra alrededor del horario: el profesor, las otras secciones y el semestre.
  def panel
    {curso: @curso, seccion: @seccion, origen: @origen, capas: CapasDelHorario.new(@seccion).para_grilla}
  end

  # El horario de la sección de origen, en bloques nuevos: la grilla los muestra y los manda como nuevos.
  def copiar_horario
    horario = @seccion.build_timetable
    @origen.timetable.timeblocks.sort_by { |b| [Timeblock.days[b.day], b.inicio_en_minutos] }.each do |b|
      horario.timeblocks.build(day: b.day, start_time: b.start_time, end_time: b.end_time, modality: b.modality,
                               classroom: b.classroom)
    end
  end

  # El de la última sección de la asignatura: en este período o, si es la primera, la última vez que se dictó.
  # Varía mucho (50, 30, 15, 25…), así que no hay un fijo que sirva.
  def cupo_sugerido
    @curso.sections.order(:created_at).last&.capacity ||
      Section.joins(:course).where(courses: {subject_id: @curso.subject_id}).order(created_at: :desc).first&.capacity
  end

  # Los códigos que tuvo la asignatura la última vez que se dictó, en otro período.
  def codigos_de_la_vez_anterior
    anterior = Course.joins(:sections).where(subject_id: @curso.subject_id).where.not(id: @curso.id)
                     .order('courses.created_at DESC').first
    anterior ? anterior.sections.pluck(:code) : []
  end

  # El código más usado en el período, para una asignatura que nunca tuvo secciones.
  def codigo_frecuente
    @curso.academic_process.sections.group(:code).order(Arel.sql('COUNT(*) DESC')).limit(1).pluck(:code).first
  end

  def set_seccion
    @seccion = Section.find(params[:id])
  end

  def set_curso
    @curso = @seccion&.course || Course.find(params[:course_id] || params.dig(:section, :course_id))
  end

  def seccion_params
    params.require(:section).permit(:code, :capacity, :teacher_id, :separar_del_dictado, :choque_confirmado,
                                    juntar_con: [],
                                    timetable_attributes: [:id, :_destroy,
                                                           {timeblocks_attributes: %i[id day start_time end_time modality classroom _destroy]}])
  end

  def autorizar_escuela
    rechazar unless administra_escuela?(@curso.academic_process.school_id)
  end

  def autorizar_crear
    rechazar unless current_admin&.authorized_create?('Section')
  end

  def autorizar_editar
    rechazar unless current_admin&.authorized_update?('Section')
  end

  def autorizar_borrar
    rechazar unless current_admin&.authorized_delete?('Section')
  end

  def autorizar_buscar
    rechazar unless current_admin&.authorized_create?('Section') || current_admin&.authorized_update?('Section')
  end
end
