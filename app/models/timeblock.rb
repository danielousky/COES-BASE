# == Schema Information
#
# Table name: timeblocks
#
#  id           :bigint           not null, primary key
#  classroom    :string
#  day          :integer          default("Lunes")
#  end_time     :time             default(Sat, 01 Jan 2000 05:00:00.000000000 -04 -04:00)
#  modality     :integer          default("Presencial")
#  start_time   :time             default(Sat, 01 Jan 2000 03:00:00.000000000 -04 -04:00)
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  teacher_id   :bigint
#  timetable_id :bigint           not null
#
# Indexes
#
#  index_timeblocks_on_teacher_id                        (teacher_id)
#  index_timeblocks_on_timetable_and_day_and_end_time    (timetable_id,day,end_time) UNIQUE
#  index_timeblocks_on_timetable_and_day_and_start_time  (timetable_id,day,start_time) UNIQUE
#  index_timeblocks_on_timetable_id                      (timetable_id)
#
# Foreign Keys
#
#  fk_rails_...  (timetable_id => timetables.id)
#
class Timeblock < ApplicationRecord
  belongs_to :teacher, optional: true
  belongs_to :timetable
  has_one :section, through: :timetable

  # El horario de clases, de 6:00 am a 10:00 pm, como en FAU (23-nov). Hasta entonces la regla miraba solo la hora
  # (de las 6 a las 21) y decía «9:00pm», pero dejaba pasar hasta las 9:59 pm: hay clases que terminan a las 9:45.
  HORA_MINIMA = 6       # 6:00 am
  HORA_MAXIMA = 22      # 10:00 pm
  DURACION_MINIMA = 30  # minutos

  enum modality: { Presencial: 0, Virtual: 1 }
  enum day: { Lunes: 0, Martes: 1, Miércoles: 2, Jueves: 3, Viernes: 4, Sábado: 5 }

  validates :day, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true
  validate :dentro_del_horario_de_clases

  # Dentro del horario de clases y de media hora por lo menos, en minutos del día. El mensaje dice de qué bloque se
  # trata («Lunes de 7:00 pm a 7:15 pm: dura menos de 30 minutos»): la grilla los guarda todos a la vez.
  def dentro_del_horario_de_clases
    return unless start_time && end_time

    fuera = { start_time: inicio_en_minutos, end_time: fin_en_minutos }
            .reject { |_, minutos| minutos.between?(HORA_MINIMA * 60, HORA_MAXIMA * 60) }
    fuera.each_key do |campo|
      errors.add(campo, "#{dia_y_horas}: #{hora_corta(send(campo))} está fuera del horario de clases (6:00 am a 10:00 pm)")
    end
    return if fuera.any?

    if fin_en_minutos <= inicio_en_minutos
      errors.add(:end_time, "#{dia_y_horas}: termina antes de empezar")
    elsif fin_en_minutos - inicio_en_minutos < DURACION_MINIMA
      errors.add(:end_time, "#{dia_y_horas}: dura menos de #{DURACION_MINIMA} minutos")
    end
  end

  # Las horas en minutos del día (7:30 pm → 1170). La base guarda la hora en UTC: leída en Caracas, una hora de las
  # 8 pm en adelante vuelve con fecha 31-dic-1999 y las demás con 1-ene-2000. Restándolas o con .to_i, una clase de
  # 6:00 a 8:30 pm, tal como se lee de la base, «terminaba antes de empezar»: no chocaba con nada al reservar cupo.
  def inicio_en_minutos
    start_time && start_time.hour * 60 + start_time.min
  end

  def fin_en_minutos
    end_time && end_time.hour * 60 + end_time.min
  end

  # Si este bloque y otro caen el mismo día a horas que se pisan.
  def se_pisa_con?(otro)
    return false unless day == otro.day
    return false unless [inicio_en_minutos, fin_en_minutos, otro.inicio_en_minutos, otro.fin_en_minutos].all?

    inicio_en_minutos < otro.fin_en_minutos && otro.inicio_en_minutos < fin_en_minutos
  end

  # «LINGÜÍSTICA I (A1), Lunes de 6:00 pm a 8:30 pm»: para avisar con qué choca una reserva.
  def descripcion_del_choque
    seccion = timetable&.section
    "#{seccion&.subject&.name} (#{seccion&.code}), #{dia_y_horas}"
  end

  # «Lunes de 6:00 pm a 8:30 pm»
  def dia_y_horas
    "#{day} de #{hora_corta(start_time)} a #{hora_corta(end_time)}"
  end

  # «6:00 pm»
  def hora_corta(hora)
    hora&.strftime('%-I:%M %P')
  end

  # Lo que la grilla semanal necesita de cada bloque (timetables/_horario_semanal y el panel de la Programación).
  # «original» es lo que tiene la base: un bloque guardado que cambió de día u hora viaja como borrar + nuevo (ver
  # horario_semanal_controller.js). «borrados»: el horario entero se va a borrar, porque no le quedó ningún bloque.
  def self.para_grilla(bloques, borrados: false)
    hhmm = ->(hora) { hora&.strftime('%H:%M') }
    bloques.map do |b|
      original = if b.persisted?
                   {dia: b.day_in_database, inicio: hhmm.(b.start_time_in_database), fin: hhmm.(b.end_time_in_database),
                    modalidad: b.modality_in_database, aula: b.classroom_in_database.to_s}
                 end
      {id: b.id, dia: b.day, inicio: hhmm.(b.start_time), fin: hhmm.(b.end_time), modalidad: b.modality,
       aula: b.classroom.to_s, borrar: borrados || b.marked_for_destruction?, original: original}
    end
  end

  validates :modality, presence: true
  
  # Que dos bloques del mismo día no empiecen ni terminen a la misma hora lo revisa el horario, con los bloques que
  # se van a guardar y no con la base: Timetable#bloques_sin_repetir_hora.

  after_save :update_timetable_name
  
  # FUNCITONS
  def short_name
    if day and start_time and end_time      
      start_format = (start_time.to_a[1]&.to_i.eql? 0) ? "%I%P" : "%I:%M%P"
      end_format = (end_time.to_a[1]&.to_i.eql? 0) ? "%I%P" : "%I:%M%P"
      aux = "#{day[0..1]} #{I18n.l(start_time, format: start_format)} #{I18n.l(end_time, format: end_format)}" 
      aux += "| #{classroom}" unless classroom.blank?
      return aux
    end

  end

  def select_de_modalidad
    "#{ApplicationController.helpers.select_tag 'bloquehorarios[modalidad][]', ApplicationController.helpers.options_for_select(Timeblock.modalities.keys{|mo| mo.titleize}, self.modality) , class: ' form-control form-control-sm'}"
  end

  def name
    "#{day} : #{start_time_to_schedule} a #{end_time_to_schedule} (#{virtual_letter}) "    
  end
  # FUNCTIONS FOR SCHEDULES
  def start_time_to_schedule
    start_time.strftime("%I:%M%P")
  end

  def end_time_to_schedule
    end_time.strftime("%I:%M%P")
  end

  def title
    "#{start_time.strftime("%H:%M")} - #{end_time.strftime("%H:%M")}"
  end
  def virtual_letter
    modality[0..4].titleize
  end
  def day_to_letter
    if day.eql? 'Miércoles'
      'X'
    else
      day.first.upcase
    end
  end

  def same_block? timetable_id
    aux = Timetable.find timetable_id

    bloquesOrigen = aux.timeblocks.map{|bh| bh.day_and_start}

    bloquesOrigen.include? day_and_start
  end

  def day_and_start
    "#{day} #{start_desc}"
  end
  def start_desc
    Timeblock.hour_description start_time
  end

  def end_desc
    Timeblock.hour_description end_time
  end

  def self.hour_description time
    if time
      if I18n.l(time, format: '%M').eql? '00'
        return I18n.l(time, format: '%I%P')
      else
        return I18n.l(time, format: '%I%M%P')
      end
    else
      return ""
    end
  end

  rails_admin do
    visible false
    list do
      field :day
      field :start_time do
        formatted_value do
          value ? I18n.l(value, format: '%H:%M') : ''
        end
      end
      field :end_time do
        formatted_value do
          value ? I18n.l(value, format: '%H:%M') : ''
        end
      end
      field :modality
      field :timetable
    end
    edit do
      field :day
      field :start_time do
        html_attributes do
          { step: '900' } # 15 minutes step
        end
      end

      field :end_time
      field :modality
      # Sin profesor por bloque (Daniel, 20-nov): ninguna pantalla lo mostraba, todas usan el de la sección, y
      # confundía. La columna teacher_id sigue en la base con lo que ya tenía.
      field :classroom do
        html_attributes do
          {:onInput => "$(this).val($(this).val().toUpperCase().replace(/[^A-Za-z0-9| ]/g,''))"}
        end        
      end
    end
  end

  private

  def update_timetable_name
    timetable.update(name: timetable.description) if timetable.present?
  end

end
