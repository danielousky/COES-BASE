# == Schema Information
#
# Table name: secciones
#
#  id              :bigint           not null, primary key
#  abierta         :integer
#  calificada      :integer
#  capacidad       :integer
#  numero          :string(255)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  asignatura_id   :string(255)
#  periodo_id      :string(255)
#  profesor_id     :string(255)
#  tipo_seccion_id :string(255)
#
# Indexes
#
#  index_secciones_on_asignatura_id                            (asignatura_id)
#  index_secciones_on_numero_and_periodo_id_and_asignatura_id  (numero,periodo_id,asignatura_id) UNIQUE
#  index_secciones_on_periodo_id                               (periodo_id)
#  index_secciones_on_profesor_id                              (profesor_id)
#  index_secciones_on_tipo_seccion_id                          (tipo_seccion_id)
#
# Foreign Keys
#
#  secciones_tipo_seccion_id_fkey  (tipo_seccion_id => tipo_secciones.id)
#
class Seccion < ApplicationRecord

	self.table_name = 'secciones'
	# ASOCIACIONES:
	belongs_to :asignatura
	belongs_to :periodo
	belongs_to :tipo_seccion
	belongs_to :profesor, optional: true 
	has_one :departamento, through: :asignatura
	has_one :catedra, through: :asignatura
	has_one :escuela, through: :departamento
	has_one :horario, dependent: :delete
	accepts_nested_attributes_for :horario

	# En realdiad esta relación no es posible porque no existe una relación directa con la clase bitacoras. Es parte del diseño de polimorfismo de clases (Bitacorables) porque el campo id_objeto no está asociado explicitamente a una sección sino a cualquier clase.
	has_many :bitacoras#, dependent: :delete_all # Sí se coloca esta dependencia al eliminar se genera un error

	has_many :inscripcionsecciones, dependent: :delete_all, class_name: 'Inscripcionseccion'
	accepts_nested_attributes_for :inscripcionsecciones

	has_many :estudiantes, through: :inscripcionsecciones, source: :estudiante

	has_many :secciones_profesores_secundarios,
		class_name: 'SeccionProfesorSecundario', dependent: :delete_all
	accepts_nested_attributes_for :secciones_profesores_secundarios

	has_many :profesores, through: :secciones_profesores_secundarios, source: :profesor

    # VALIDACIONES:
    validates :asignatura_id, presence: true
    # validates :profesor_id, presence: true, if: :new_record?
    validates :periodo_id, presence: true
    validates :numero, presence: true
	validates_uniqueness_of :numero, scope: [:periodo_id, :asignatura_id], message: 'La sección ya existe, inténtalo de nuevo!', field_name: false

	before_create :default_values

    # SCOPES:
    scope :con_inscripciones, -> {joins(:inscripcionsecciones).group('secciones.id').having('count(inscripcionsecciones.id) > 0')}
    scope :sin_inscripciones, -> {joins(:inscripcionsecciones).group('secciones.id').having('count(inscripcionsecciones.id) < 1')}
    scope :trimestrales, -> {joins(:inscripcionsecciones).where("inscripcionsecciones.estado = 4 or inscripcionsecciones.estado = 5")}
    scope :trimestrales1, -> {joins(:inscripcionsecciones).where("inscripcionsecciones.estado = 4")}
    scope :trimestrales2, -> {joins(:inscripcionsecciones).where("inscripcionsecciones.estado = 5")}
	scope :calificadas, -> {where "calificada IS TRUE"}
	scope :sin_calificar, -> {where "calificada IS NOT TRUE"}
	scope :del_departamento, lambda {|dpto_id| joins(:asignatura).where('asignaturas.departamento_id = ?', dpto_id)}
	scope :del_periodo, -> (periodo_id) {where "periodo_id = ?", periodo_id}
	scope :de_la_escuela, -> (escuela_id) {joins({asignatura: :departamento}).where("departamentos.escuela_id = ?", escuela_id)}

	# scope :del_periodo_actual, -> { where "periodo_id = ?", ParametroGeneral.periodo_actual_id}

	scope :con_cupos, -> {joins(:inscripcionsecciones).group('secciones.id').having('count(inscripcionsecciones.id) < secciones.capacidad').order('count(inscripcionsecciones.id)')}

	scope :order_by_total_inscripciones, -> {joins(:inscripcionsecciones).order('inscripcionsecciones.id')}

	# scope :order_by_total_inscripciones, -> {joins(:inscripcionsecciones).order('inscripcionsecciones.')}

	# FUNCIONES:
	def programacion
		Programacion.find_or_create_by(asignatura_id: asignatura_id, periodo_id: periodo_id)
	end

	def find_or_create_section

		code = numero
		course = programacion.find_or_create_course
		modality = I18n.t("activerecord.scopes.section."+tipo_seccion_id)
		if course and code and modality
			section = Section.where(course_id: course.id, code: code, modality: modality).first
			if section.nil?
				qualified = calificada
				capacity = capacidad
				capacity ||= 30

				@teacher = profesor.find_teacher if profesor
				section = Section.create(course_id: course.id, code: code, modality: modality, capacity: capacity, qualified: qualified, teacher_id: @teacher&.id)

			end
			return section
		end
	end

	def find_section
		code = numero
		course = programacion.find_or_create_course
		modality = I18n.t("activerecord.scopes.section."+tipo_seccion_id)	
		Section.where(course_id: course.id, code: code, modality: modality).first
	end


	def estudiante_inscrito? estudiante_ci
		inscripciones.map{|ins| ins.estudiante_id}.include? estudiante_ci.to_s
	end

	def hay_cupos?
		self.capacidad and (self.capacidad > 0) and (self.total_estudiantes < self.capacidad)
	end

	def descripcion_con_cupos
		"#{numero} - (#{capacidad_vs_inscritos})"
	end

	def escuelaperiodo
		Escuelaperiodo.where(periodo_id: self.periodo_id, escuela_id: self.escuela.id).first
	end

	# FUNCION Temporal de actualizacion de Periodos E y S
	def self.actualizar_periodos
		secciones_actualizadas = 0
		Seccion.where("periodo_id like '%E%'").each do |se| 
			aux_pe_id = se.periodo_id
			aux_pe_id[aux_pe_id.length-1] = "S"
			se.periodo_id = aux_pe_id
			secciones_actualizadas += 1 if se.save
		end

		total_existentes = 0
		total_nuevas = 0
		Programacion.where("periodo_id like '%E%'").each do |pr|

			aux_pe_id = pr.periodo_id
			aux_pe_id[aux_pe_id.length-1] = "S"

			begin
				total_nuevas +=1 if Programacion.create(periodo_id: aux_pe_id, asignatura_id: pr.asignatura_id)
			rescue Exception => e
				puts "Programacion Ya Exitente: #{e}"
				total_existentes += 1
			end
		end

		planes_actualizados = 0

		Historialplan.where("periodo_id like '%E%'").each do |plan|
			aux_pe_id = plan.periodo_id
			aux_pe_id[aux_pe_id.length-1] = "S"
			plan.periodo_id = aux_pe_id
			planes_actualizados += 1 if plan.save
		end
		# Secciones:
		p " Total Secciones actualizadas: #{secciones_actualizadas} ".center(200, "=")

		# Programaciones:
		total_a_eliminar = Programacion.where("periodo_id like '%E%'").count
		p " Total programaciones Existentes: #{total_existentes} ".center(200, "*")
		p " Total programaciones Creadas: #{total_nuevas} ".center(200, "*")
		p " Total programaciones a eliminar: #{total_a_eliminar} ".center(200, "*")
		p ' Programaciones eliminadas' if Programacion.where("periodo_id like '%E%'").delete_all
		total_a_eliminar = Programacion.where("periodo_id like '%C%' || periodo_id like '%E%'").count
		p " Total programaciones restantes: #{total_a_eliminar} ".center(200, "*")

		# Planes:
		p " Total Planes actualizados: #{planes_actualizados} ".center(200, "=")

		# Periodos:
		total_periodos = Periodo.where("id like '%C%' || id like '%E%'").count

		p " Total Periodos eliminados: #{total_periodos} ".center(200, "^")
		Periodo.where("id like '%E%'").delete_all
		
		total_periodos = Periodo.where("id like '%C%' || id like '%E%'").count
		p " Total Periodos restantes: #{total_periodos} ".center(200, "^")

	end

	def numero_limpio_y_sin_r
		numero.delete('(R)').strip
	end

	def seccion_hermana
		if numero.include? '(R)'
			aux = Seccion.where(asignatura_id: asignatura_id, periodo_id: periodo_id, numero: numero_limpio_y_sin_r).first
			if aux
				return aux
			else
				return Seccion.where(asignatura_id: asignatura_id, periodo_id: periodo_id).first
			end
		else
			return Seccion.where(asignatura_id: asignatura_id, periodo_id: periodo_id).first
		end
	end
	def es_de_reparacion?
		numero.include? '(R)' or numero.eql? 'R'
	end

	def todos_profes
		ids = profesores.ids
		ids.push profesor_id

		Profesor.where(usuario_id: ids)
	end

	def unico_profesor?
		(not profesor.nil? and profesores.count.eql? 0)
	end

	def mas_de_uno?
		profesores_totales > 1
	end

	def profesores_totales
		aux = profesor_id ? 1 : 0
		aux += profesores.count
	end

	def total_calificados
	self.inscripciones.con_calificacion.count
	end

	def notas
		self.inscripciones.each{|ins| p ins.calificacion_final}
	end

	def inscripciones
		self.inscripcionsecciones
	end
	def inscripciones_incluidas
		self.inscripcionsecciones.includes(:inscripcionseccion)
	end

	def promedio
		self.inscripcionsecciones.average("calificacion_final").to_i#f.round(2)
	end

	def maximo
		self.inscripcionsecciones.max("calificacion_final").to_i
	end

	def habilitada_para_calificadar_recientemente?
		fecha_ultima_calificacion = Bitacora.where("tipo_objeto = 'Seccion' and id_objeto = :id and descripcion LIKE :desc", id: self.id, desc: '%para calificar trimestral%').last

		if fecha_ultima_calificacion.nil?
			return false
		else
			fecha_ultima_calificacion = fecha_ultima_calificacion.created_at
			if (fecha_ultima_calificacion + 2.week) > Date.today
				return true
			else
				return false
			end
		end
	end


	def tr_estilo_estado
		self.calificada ? 'table-success' : ''

	end

	def recientemente_calificada?
		fecha_ultima_calificacion = Bitacora.where("tipo_objeto = 'Seccion' and id_objeto = :id and descripcion LIKE :desc", id: self.id, desc: '%Seccion Calificada%').last

		if fecha_ultima_calificacion.nil?
			return false
		else
			fecha_ultima_calificacion = fecha_ultima_calificacion.created_at
			if (fecha_ultima_calificacion + 6.week) > Date.today
				return true
			else
				return false
			end
		end
	end


	def colocar_reciente_estado_calificacion

		calificada_reciente = self.recientemente_calificada?

		tipo_adicional = 'info'
		size = 11
		mensaje = 'Pendiente por calificar'
		if self.tiene? 0 # Sin Calificar
			mensaje = 'Pendiente por calificar 1er. Trimestre'
			tipo_adicional = 'warning'
		elsif self.tiene_trimestres1?
			if calificada_reciente
				mensaje = '1er. Trimestre calificado'
			else
				size = 12
				mensaje = 'Pendiente por calificar 2do. Trimestre'
				tipo_adicional = 'warning'
			end
			
		elsif self.tiene_trimestres2?
			if calificada_reciente
				mensaje = '2do. Trimestre calificado'
			else
				size = 12
				mensaje = 'Pendiente por calificar 3er. Trimestre'
				tipo_adicional = 'warning'

			end
		end
		return "<div class='badge badge-#{tipo_adicional}' style='font-size: #{size}px;'>#{mensaje}</div>"
	end


	def tiene_trimestres1?
		# self.tiene? 4
		self.inscripcionsecciones.trimestre1.any?
	end

	def tiene_trimestres2?
		# self.tiene? 5
		self.inscripcionsecciones.trimestre2.any?
	end

	def tiene? del_estado
		self.inscripcionsecciones.any? and (cuantos_tiene? del_estado).any?
	end

	def cuantos_tiene? del_estado
		self.inscripcionsecciones.group("estado").having("estado = ?", del_estado).count
	end

	def pci?
		self.asignatura.pci? self.periodo_id
	end

	def cerrada?
		!self.abierta
	end

	def abierta?
		abierta
	end

	def capacidad_vs_inscritos
		"#{self.capacidad} / #{total_estudiantes}"
	end

	def calificada_valor
		self.calificada ? 'Sí' : 'No'
	end

	def total_no_retirados
		total_estudiantes - total_retirados		
	end

	def total_estudiantes
		inscripciones.count
	end

	def total_confirmados
		inscripciones.confirmados.count
	end

	def total_aprobados
		inscripciones.aprobado.count
	end

	def total_reprobados
		inscripciones.aplazado.count
	end

	def total_retirados
		inscripciones.retirado.count
	end

	def total_perdidos
		inscripciones.perdidos.count
	end

	def total_sin_calificar
		inscripciones.sin_calificar.count
	end


	def descripcion_con_uxxi
		"(#{asignatura.id_uxxi}) - #{descripcion}"
	end

	def desc_asig_numero
		"#{asignatura.descripcion_id} (#{numero})"
	end

	def descripcion_simple
		"#{asignatura_id} (#{numero})"
	end

	def descripcion
		descrip = "#{self.periodo_id} - "
		descrip += self.asignatura.descripcion_pci self.periodo_id
		
		if numero
			if self.suficiencia?
				descrip += " (Suficiencia)"
			else
				descrip += " - #{numero}"
			end
		end 
		return descrip
	end

	def tabla_profesores_secundarios
		aux = "<table class='table mb-0'><tbody>"

		profesores.each do |profe|
			aux += "<tr><td>#{profe.descripcion}"
			aux += "<a data_confirm='¿Está seguro de esta acción?' href='/coesapp/secciones/#{id}/desasignar_profesor_secundario?profesor_id=13587081' class='tooltip-btn' data_toggle='tooltip' title='Desasignar este profesor'><i class='glyphicon glyphicon-minus text-danger'></i></a>"
			aux += "</td></tr>"
		end

		aux += "<tr><td><a href='/coesapp/secciones/#{id}/seleccionar_profesor?sec=true' class='tooltip-btn' data_toggle='tooltip' title='Agregar profesor secundario'><i class='glyphicon glyphicon-plus text-success'></i></a></td></tr>"

		aux += '</tbody></table>'

	end

	def descripcion_escuela
		"#{descripcion} (#{escuela.descripcion})"
	end

	# Se convirtió en un partial 
	# def descripcion_profesor_asignado_edit
		
	# 	if profesor
	# 		aux = profesor.descripcion_usuario
	# 	else
	# 		aux = "No asignado"
	# 	end

	# 	aux += " <a role='button' class='tooltip-btn' data_toggle='tooltip' title='Actualizar Tutor-Calificador' href=#{seleccionar_profesor_seccion_path(self.id)}><span class='glyphicon glyphicon-pencil'></span></a> "
	# end

	
	def descripcion_profesor_asignado
		if profesor
			profesor.descripcion_usuario
		else
			"No asignado"
		end
	end

	def ejercicio
		"#{periodo_id}"
	end

	def r_or_f?
		if numero.include? 'R'
			return 'R'
		else 
			'F'
		end
	end

	# end


	def suficiencia?
		# return numero.include? 'S'
		self.tipo_seccion_id.eql? TipoSeccion::SUFICIENCIA
	end

	def tipo_convocatoria
		"F#{self.periodo.valor_para_tipo_convocatoria}"
	end

	# def tipo_convocatoria
	# 	aux = numero[0..1]
	# 	if reparacion?
	# 		aux = "RA2" #{aux}"
	# 	else
	# 		aux = "FA2" #"F#{aux}"
	# 	end
	# 	return aux
	# end

	def acta_no
		"#{self.asignatura.id_uxxi}#{self.numero}#{self.periodo_id}"
	end

	# FUNCIONES PROTEGIDAS

	protected

	def default_values
		self.tipo_seccion_id ||= 'NF'
		self.calificada ||= false
	end

end
