# == Schema Information
#
# Table name: historialplanes
#
#  id            :bigint           not null, primary key
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  escuela_id    :string(255)
#  estudiante_id :string(255)
#  grado_id      :bigint
#  periodo_id    :string(255)
#  plan_id       :string(255)
#
# Indexes
#
#  fk_rails_d7a1d63156                     (grado_id)
#  index_historialplanes_on_escuela_id     (escuela_id)
#  index_historialplanes_on_estudiante_id  (estudiante_id)
#  index_historialplanes_on_periodo_id     (periodo_id)
#  index_historialplanes_on_plan_id        (plan_id)
#  index_unique                            (estudiante_id,periodo_id) UNIQUE
#  unique_historial                        (estudiante_id,escuela_id,periodo_id,plan_id) UNIQUE
#
class Historialplan < ApplicationRecord
	self.table_name = 'historialplanes'

	belongs_to :periodo
	belongs_to :plan, primary_key: :id

	belongs_to :grado
	has_one :estudiante, through: :grado
	has_one :escuela, through: :grado

	# OJO: Esta debe ser la validación: Que un estudiante no tenga más de un plan para un mismo periodo
	validates_uniqueness_of :grado_id, scope: [:periodo_id], message: 'El estudiante ya tiene un plan para el periodo y escuela', field_name: false

	validates :grado_id, presence: true

	scope :por_escuela, lambda { |escuela_id| joins(:plan).where('planes.escuela_id': escuela_id)}

	def descripcion
		"#{plan.descripcion_completa} - Desde #{periodo_id}"
	end

	def actualizar_planes_grados
		grade = self.grado.find_grade
		if plan
			sp = StudyPlan.where(code: plan_id).first
			grade.update(study_plan_id: sp.id) ? true : false
		else
			false
		end
	end

	def self.carga_inicial
		begin
			Estudiante.where("plan IS NOT NULL").each do |e|
				if e.plan and e.plan.include? '290'
					plan_id = Plan.where("id LIKE '%290%'").limit(1).first.id
				elsif e.plan and e.plan.include? '280'
					plan_id = Plan.where("id LIKE '%280%'").limit(1).first.id
				else
					plan_id = Plan.where("id LIKE '%270%'").limit(1).first.id
				end

				print "ID: #{e.id}--- Plan: #{plan_id} .#{e.plan}."
				HistorialPlan.create(estudiante_id: e.id, plan_id: plan_id)
			end			
		rescue Exception => e
			return e
		end
	end

end
