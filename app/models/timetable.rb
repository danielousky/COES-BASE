# == Schema Information
#
# Table name: timetables
#
#  id         :bigint           not null, primary key
#  color      :string
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  section_id :bigint           not null
#
# Indexes
#
#  index_timetables_on_section_id  (section_id)
#
# Foreign Keys
#
#  fk_rails_...  (section_id => sections.id)
#
class Timetable < ApplicationRecord
  belongs_to :section
  has_one :subject, through: :section


	has_many :timeblocks, dependent: :destroy
	accepts_nested_attributes_for :timeblocks, allow_destroy: true

	validates :section, presence: true, uniqueness: true
  validates :color, presence: true#, format: { with: /\A\d{1,3},\d{1,3},\d{1,3}\z/, message: 'Debe ser un color RGB en formato "r,g,b".' }

  after_initialize :set_default_color, if: :new_record?

  validates :timeblocks, presence: true, length: { minimum: 1, message: 'Debe tener al menos un bloque horario.' }
  validate :bloques_sin_repetir_hora

  # Dos bloques del mismo día no empiezan ni terminan a la misma hora (lo mismo piden los índices únicos de la base).
  # Se revisan los bloques que se van a guardar, en memoria (23-nov). Antes cada bloque se revisaba contra la base,
  # donde siguen los que se van a mover o a borrar, y al juntar o mover bloques en la grilla salía un error falso:
  # «Ya existe un bloque horario con una hora de entrada igual para el horario».
  def bloques_sin_repetir_hora
    quedan = timeblocks.reject(&:marked_for_destruction?)
    { inicio_en_minutos: 'empiezan', fin_en_minutos: 'terminan' }.each do |hora, verbo|
      quedan.group_by { |b| [b.day, b.send(hora)] }.each do |(dia, minutos), iguales|
        next if dia.nil? || minutos.nil? || iguales.size < 2

        errors.add(:base, "Dos bloques del #{dia} #{verbo} a la misma hora: #{iguales.map(&:dia_y_horas).join(' y ')}")
      end
    end
  end

  scope :without_timeblocks, -> {left_outer_joins(:timeblocks).where(timeblocks: { id: nil }) }

  rails_admin do
    navigation_label 'Planif. Periódica'
    navigation_icon 'fa-solid fa-clock'
    visible false
    list do
      field :section
      field :name
      field :color do
        formatted_value do
          value ? "<span style='background-color: #{value}; width: 20px; height: 20px; display: inline-block;'></span>".html_safe : ''
        end
      end
      field :timeblocks do
        formatted_value do |v|
          v.map { |bh| bh.name }.to_sentence if v.present?
        end
      end
    end
    show do
      field :section
      field :color do
        formatted_value do
          value ? "<span style='background-color: #{value}; width: 20px; height: 20px; display: inline-block;'></span>".html_safe : ''
        end
      end
      field :timeblocks
    end    
    edit do
      field :color do
        read_only true
        formatted_value do
          value ? "<label style='background-color: #{value}; width: 20px; height: 20px; display: inline-block;'></span>".html_safe : ''
        end
      end
      field :timeblocks
    end

    export do
      field :section
      field :name
      field :timeblocks do
        formatted_value do |v|
          v.map { |bh| "#{bh.day[0..2]} de #{bh.start_time_to_schedule} a #{bh.end_time_to_schedule} #{bh.virtual_letter}" }.to_sentence if v.present?
        end
      end

    end

  end

	def description_section
		"#{section.subject&.code} (#{section.code}) #{section.teacher&.user&.short_name}"
	end


	def description
		timeblocks.collect{|bh| "#{bh.day[0..2]} de #{bh.start_time_to_schedule} a #{bh.end_time_to_schedule} (#{bh.modality.titleize}) "}.to_sentence
	end

	def bloques_schedule
		timeblocks.collect{|bh| {day: Timeblock.days[bh.day], periods: [["#{bh.start_time_to_schedule}", "#{bh.end_time_to_schedule}"]], title: bh.title, color: self.color} }
	end

  def generate_color
    # Genera un color similar al de subject, variando ligeramente cada componente
    base_color = subject&.color
    if base_color.present?# && base_color =~ /\A(\d{1,3}),(\d{1,3}),(\d{1,3})\z/
      r, g, b = base_color.split(',').map(&:to_i)
      # Variar cada componente en ±20, manteniéndolo en el rango 0..255
      r = [[r + rand(-20..20), 0].max, 255].min
      g = [[g + rand(-20..20), 0].max, 255].min
      b = [[b + rand(-20..20), 0].max, 255].min
      "#{r},#{g},#{b}"
    else
      # Si no hay color base, generar uno pastel aleatorio
      "#{rand(150..230)},#{rand(150..230)},#{rand(150..230)}"
    end
  end

	def color_rgb_to_hex intensidad = nil
		if color.blank?
			"101010"
		else
			r,g,b = color.split(",")
			r = r.split("(")[1]

			if intensidad
				r = r.to_i*intensidad
				g = g.to_i*intensidad
				b = b.to_i*intensidad

				r = 235 if r > 235
				g = 235 if g > 235
				b = 235 if b > 235
			end

			"#{toHex r}#{toHex g}#{toHex b}"
		end
	end

	def transparencia_color valor
		unless color
			return ""
		else
			aux = color.split(",")
			aux[3] = "#{valor})"
			return aux
		end
	end

  private
  def set_default_color
    self.color ||= generate_color
  end

	def toHex c
		aux = c.to_i.to_s(16)
		return (aux.length.eql? 1) ? "0#{aux}" : aux
	end


end
