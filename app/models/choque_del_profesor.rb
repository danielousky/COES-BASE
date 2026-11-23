# El choque del profesor de una sección con sus otras clases del período, y las secciones que se dictan juntas
# (23-nov). Daniel eligió que la grilla avise y pida decidir: mover el bloque, «Se dictan juntas» o «Guardar igual».
#
# Se dictan juntas las que tienen el mismo profesor, a la misma hora y casi siempre en la misma aula, aunque sean de
# asignaturas distintas. En 2026-02, Canto Coral I, III, IV y V A1, los martes y jueves de 12:30 a 2:30 pm. De los 87
# pares de secciones con el mismo profesor a la vez, 63 eran a la hora exacta. Llevan el mismo número en
# sections.dictado_conjunto (el id de una de ellas: no es una referencia, es el número del grupo), y la grilla no avisa
# el choque entre ellas. Lo que viaja con el formulario lo escribe la grilla (horario_semanal_controller.js):
#
#   juntar_con            ids de otras secciones del período: al guardar, esta queda en su grupo; si ya eran de
#                         grupos distintos, los grupos se funden
#   separar_del_dictado   «1»: al guardar, esta sale de su grupo; si en el grupo queda una sola, deja de ser grupo
#   revisar_choques       lo pone la Programación (ProgramacionSeccionesController): no guarda si el cambio trae un
#                         choque nuevo del profesor (CapasDelHorario#choques_nuevos). La grilla ya lo avisó: esto
#                         cubre lo que otro asistente guardó mientras tanto. El admin no lo revisa
#   choque_confirmado     «1»: el asistente eligió «Guardar igual»
#
# Cada período lleva sus grupos. Clonar la Programación copia el número a las secciones del período nuevo, que quedan
# juntas entre ellas (AcademicProcessesController#clone_sections).
module ChoqueDelProfesor
  extend ActiveSupport::Concern

  included do
    attr_accessor :juntar_con, :separar_del_dictado, :revisar_choques, :choque_confirmado

    validate :sin_choques_nuevos_del_profesor, if: :revisar_choques
    before_save :preparar_dictado_conjunto
    after_save :juntar_las_demas
    after_destroy :salir_del_dictado
  end

  # Las otras secciones que se dictan junto con esta, tal como está guardada.
  def juntas
    return Section.none unless dictado_conjunto_in_database

    del_dictado(dictado_conjunto_in_database).where.not(id: id)
  end

  # Los ids de las que se van a dictar junto con esta cuando se guarde (con juntar_con y separar_del_dictado).
  def juntas_al_guardar
    otras = secciones_para_juntar.to_a
    de_sus_grupos = del_dictado(otras.filter_map(&:dictado_conjunto)).ids
    ((separar_del_dictado? ? [] : juntas.ids) + otras.map(&:id) + de_sus_grupos).uniq - [id]
  end

  # Para el aviso al guardar: si el cambio la junta con otras o la separa de las suyas.
  def cambia_el_dictado_conjunto?
    secciones_para_juntar.exists? || (separar_del_dictado? && dictado_conjunto_in_database.present?)
  end

  private

  def separar_del_dictado?
    ActiveModel::Type::Boolean.new.cast(separar_del_dictado) || false
  end

  def sin_choques_nuevos_del_profesor
    return if course.nil? || ActiveModel::Type::Boolean.new.cast(choque_confirmado)

    CapasDelHorario.new(self).choques_nuevos.each { |texto| errors.add(:base, texto) }
  end

  def del_periodo
    return Section.none if course.nil?

    Section.joins(course: :academic_process).where(academic_processes: {period_id: course.academic_process.period_id})
  end

  def del_dictado(grupo)
    del_periodo.where(dictado_conjunto: grupo)
  end

  def secciones_para_juntar
    ids = Array(juntar_con).compact_blank.map(&:to_i) - [id]
    ids.empty? ? Section.none : del_periodo.where(id: ids)
  end

  def preparar_dictado_conjunto
    @dictado_que_deja = @otras_a_juntar = @grupos_a_fundir = nil
    if separar_del_dictado?
      @dictado_que_deja = dictado_conjunto_in_database
      self.dictado_conjunto = nil
    end
    otras = secciones_para_juntar.to_a
    return if otras.empty?

    @grupos_a_fundir = [dictado_conjunto, *otras.map(&:dictado_conjunto)].compact.uniq
    @otras_a_juntar = otras.map(&:id)
    self.dictado_conjunto = @grupos_a_fundir.min || @otras_a_juntar.min
  end

  # Las demás no pasan por sus validaciones ni dejan versión: solo cambia el número del grupo, y la versión de esta
  # sección dice quién las juntó. Lo que decidió el aviso vale para este guardado: el siguiente no lo repite.
  def juntar_las_demas
    if @otras_a_juntar.present?
      ids = @otras_a_juntar + del_dictado(@grupos_a_fundir).ids - [id]
      Section.where(id: ids).update_all(dictado_conjunto: dictado_conjunto)
    end
    disolver_si_queda_una(@dictado_que_deja) if @dictado_que_deja
    self.juntar_con = self.separar_del_dictado = self.choque_confirmado = nil
  end

  def salir_del_dictado
    disolver_si_queda_una(dictado_conjunto) if dictado_conjunto
  end

  def disolver_si_queda_una(grupo)
    quedan = del_dictado(grupo).ids
    Section.where(id: quedan).update_all(dictado_conjunto: nil) if quedan.size == 1
  end
end
