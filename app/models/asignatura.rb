# == Schema Information
#
# Table name: asignaturas
#
#  id                :string(255)      not null, primary key
#  activa            :integer
#  anno              :integer
#  calificacion      :integer
#  creditos          :integer
#  descripcion       :string(255)
#  forzar_absoluta   :integer
#  id_uxxi           :string(255)
#  orden             :integer
#  pci               :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catedra_id        :string(255)      not null
#  departamento_id   :string(255)      not null
#  tipoasignatura_id :string(255)      not null
#
class Asignatura < ApplicationRecord

	# ASOCIACIONES:
	belongs_to :catedra
	belongs_to :departamento
	belongs_to :tipoasignatura

	has_many :dependencias, dependent: :delete_all
	has_many :dependencia_hacia_atras, foreign_key: 'asignatura_dependiente_id', class_name: 'Dependencia'
	# has_many :asignaturas, through: :dependencias

	def asignaturas
		depen_ids = asi.dependencias.map{|dep| dep.asignatura_dependiente_id}
		Asignatura.where('id IN (?)', depen_ids)
	end


	has_many :programaciones, dependent: :destroy
	has_many :periodos, through: :programaciones

	# belongs_to :catedra_departamento, class_name: 'CatedraDepartamento', foreign_key: [:catedra_id, :departamento_id], primary_key: [:catedra_id, :departamento_id]

	# ENUMERADAS CONSTANTES
	enum calificacion: [:numerica, :absoluta, :numerica3]

	has_one :escuela, through: :departamento
	has_many :secciones
	accepts_nested_attributes_for :secciones

	# VALIDACIONES:
	validates :id, presence: true, uniqueness: true
	validates_uniqueness_of :id_uxxi, message: 'Código UXXI ya está en uso', field_name: false	
	validates_presence_of :id_uxxi, message: 'Código UXXI requerido'	
	validates :descripcion, presence: true
	validates :calificacion, presence: true
	# validates :anno, presence: true
	# validates :orden, presence: true
	validates :catedra_id, presence: true
	validates :departamento_id, presence: true
	validates :tipoasignatura_id, presence: true

	# SCOPE
	scope :sin_dependencias, -> {joins('LEFT JOIN dependencias ON dependencias.asignatura_id = asignaturas.id').where('dependencias.asignatura_id IS NULL')}
	scope :con_dependencias, -> {joins(:dependencias).distinct}

	# Libres de dependencias hacia atrás
	scope :independientes, -> {joins('LEFT JOIN dependencias ON dependencias.asignatura_dependiente_id = asignaturas.id').where('dependencias.asignatura_dependiente_id IS NULL')}

	# PENDIENTE POR RESOLVER
	# Con dependencias hacia atrás

	# scope :dependientes, -> {joins('INNER JOIN dependencias ON dependencias.asignatura_dependiente_id = asignaturas.id').where('dependencias.asignatura_dependiente_id IS NULL')}

	scope :del_departamento, lambda {|dpto_id| where(departamento_id: dpto_id)}

	scope :activas, lambda { |periodo_id| joins(:programaciones).where('programaciones.periodo_id = ?', periodo_id) }

	scope :pcis, lambda { |periodo_id| joins(:programaciones).where('programaciones.periodo_id = ? and programaciones.pci IS TRUE', periodo_id) }

	scope :no_pcis, lambda { |periodo_id| joins(:programaciones).where('programaciones.periodo_id = ? and programaciones.pci IS FALSE', periodo_id) }

	scope :de_escuela, lambda {|escuela_id| joins(:escuela).where('escuelas.id': escuela_id)}
	scope :sin_la_escuela, -> (escuela_id){joins(:escuela).where.not('escuelas.id': escuela_id)}

	# scope :pcis, -> {where('pci IS TRUE')}
	# scope :no_pcis, -> {where('pci IS FALSE')}


	# TRIGGGERS:
	before_save :set_uxxi_how_id
	before_save :set_to_upcase, :if => :new_record?

	# FUNCIONES:

	def self.updated_codes_subjects
		Asignatura.where.not("id ILIKE '0%'").each do |asig|
			aux = "0#{asig.id}"
			sub = Subject.find_by(code: aux)
			if sub
				print sub.update!(code: asig.id) ? '√' : 'X'
			else
				print '='
			end
		end
	end	

	def arbol_completo_dependencias
		aux = []
		aux << arbol_dependencias
		aux << arbol_dependencias_hacia_atras
		return aux.flatten.uniq
	end

	def arbol_dependencias_hacia_atras
		if dependencia_hacia_atras.count.eql? 0
			self.id
		else
			dependencia_hacia_atras.map{|dep| [self.id, dep.asignatura.arbol_dependencias_hacia_atras]}
		end
	end

	def arbol_dependencias
		if dependencias.count.eql? 0
			self.id
		else
			dependencias.map{|dep| [self.id, dep.asignatura_dependiente.arbol_dependencias]}
		end
	end

	def find_subject
		Subject.find_by(code: self.id)
	end
	def import_subject
		subject = Subject.find_or_initialize_by(code: self.id)
		if subject.new_record?
			subject.active = self.activa
			subject.code = self.id_uxxi
			subject.force_absolute = self.forzar_absoluta
			subject.name = self.descripcion
			subject.ordinal = self.anno
			subject.ordinal ||= self.orden
			subject.ordinal ||= 0
			subject.qualification_type = self.calificacion
			subject.unit_credits = self.creditos
			subject.area_id = self.catedra&.find_area&.id
			subject.school_id = self.escuela&.find_school&.id
			subject.subject_type_id = self.tipoasignatura.find_subject_type&.id
			subject.save ? '+' : "X #{subject.errors.full_messages.to_sentence} #{self.id}"

		else
			'='
		end
	end


	def proyecto?
		self.tipoasignatura_id.eql? Tipoasignatura::PROYECTO
	end

	def pci? periodo_id
		programaciones.pcis.del_periodo(periodo_id).any?
	end

	def tiene_programaciones? periodo_id
		programaciones.where(periodo_id: periodo_id).count > 0
	end

	def desc_confirm_inscripcion
		"- #{self.descripcion} - #{self.creditos}"
	end

	def descripcion_id
		"#{id}: #{descripcion}"
	end

	def descripcion_id_con_creditos
		"#{descripcion_id} (#{creditos} Unidades de Créditos)"
	end

	def descripcion_pci periodo_id

		if self.pci? periodo_id
			return "#{self.descripcion} (PCI)"
		else
			self.descripcion
		end
	end
	def activa? periodo_id
		# return self.activa #self.activa.eql? true ? true : false
		self.programaciones.del_periodo(periodo_id).any?
	end

	def descripcion_id_con_escuela
		"#{descripcion_id} <span class='badge badge-success'>#{self.escuela.descripcion}</span>".html_safe
	end
	def descripcion_con_id_pci? periodo_id = nil

		aux = "#{id}: #{descripcion_completa}"
		aux += " (PCI) " if periodo_id and self.pci?(periodo_id)
		return aux
	end
	def descripcion_completa
		"#{descripcion_id} - #{catedra.descripcion_completa} - #{departamento.descripcion_completa}"
	end

	def descripcion_reversa
		desc = cal_departamento.descripcion if cal_departamento
		desc += "| #{catedra.descripcion.titleize}" if catedra		
		return desc
	end

	# FUNCIONES PROTEGIDAS:
	protected
	
	def set_uxxi_how_id
		self.id_uxxi.strip!
		self.id = self.id_uxxi if self.id != self.id_uxxi
	end

	def set_to_upcase
		self.descripcion.strip.upcase.strip!
	end
end
