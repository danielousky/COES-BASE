class AuthorizedsController < ApplicationController
	before_action :require_admin
	before_action :require_gestionar_admins

	def update_authorize
		@admin = Admin.find params[:id]

		Authorizable.all.each do |authorizable|
			authorized = Authorized.find_or_initialize_by(admin_id: @admin.id, authorizable_id: authorizable.id)
			
			param_model = params["model#{authorizable.id}"]

			authorized.can_read = (param_model and param_model[:can_read]) ? true : false
			
			authorized.can_create = (param_model and param_model[:can_create]) ? true : false
			
			authorized.can_update = (param_model and param_model[:can_update]) ? true : false
			
			authorized.can_delete = (param_model and param_model[:can_delete]) ? true : false
			
			authorized.can_import = (param_model and param_model[:can_import]) ? true : false
						
			authorized.can_export = (param_model and param_model[:can_export]) ? true : false
			
			unless authorized.save
				flash[:danger] = 'No se pudo completar de actualizar las restricciones. '
				flash[:danger] += authorized.errors.full_messages.to_sentence
				break
			end
		end

		flash[:success] = 'Restricciones de Acceso a Procesos actualizadas con éxito' if flash[:danger].nil?

		redirect_to "/admin/admin/#{@admin.id}"

	end

	private

	# Reescribir permisos es gestionar admins: ser admin no basta (antes un asistente podía darse todo)
	def require_gestionar_admins
		rechazar 'No autorizado para cambiar permisos de administradores' unless current_admin.authorized_update? 'Admin'
	end
end
