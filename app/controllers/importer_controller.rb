class ImporterController < ApplicationController
	before_action :require_admin

	def entities
		case params[:entity]
		when 'subjects'	
			require_fields = ['id', 'nombre']
		when 'students', 'teachers'
			require_fields = ['ci', 'email', 'nombres', 'apellidos'] 
		when 'sections'
			require_fields = ['numero', 'codigo', 'capacidad', 'profesor_ci'] 
		when 'academic_records'
			require_fields = ['ci', 'codigo', 'seccion'] 
		end
	
		if require_fields and params[:entity]
			begin			
				result = ImportXslx.general_import params, require_fields


				flash[:success] = "Registros Procesados: "
				flash[:success] += "#{result[0]}"+ " Nuevo".pluralize(result[0]) + " | "
				flash[:success] += "#{result[1]}"+ " Actualizado".pluralize(result[1])

				if result[2].include? 'limit_records'
					result[2].delete 'limit_records'
					flash[:success] += " | 1 advertencia"

					flash[:warning] = "¡El archivo contiene más de 500 registros! Se procesaron estos primeros 500 y quedaron pendientes el resto. Por favor, divida el archivo y realice una nueva carga. ".html_safe
				end
				
				if result[2].any? 
					flash[:success] += " | #{result[2].count}"+ " con errores."
					flash[:danger] = ""
					if result[2].count > 50
						flash[:danger] += "Más de 50 registros tienen problemas, por lo que no se continuó el proceso de carga. ".html_safe
					end
					flash[:danger] += " A continuación la(s) fila(s):columna(s)  de datos que reportan algún error: #{result[2].to_sentence}."

					if params[:entity].eql? 'academic_records'
						flash[:danger] += " Corrobore en el sistema que tanto el código de la asignatura como la cédula del estudiante que desea migrar existen. De no encontrarse la sección se creará siempre y cuando la asignatura exista. Revise los valores de los datos en el archivo de carga e inténtelo nuevamente. "
					end

					redirect_back fallback_location: root_path
				else
					redirect_to "/admin/#{params[:entity].singularize}"
				end
			rescue StandardError => e
				flash[:danger] = "Error General: #{e}"
				redirect_back fallback_location: root_path
			end
		else
			flash[:danger] = 'Tipo de entidad no encontrada. Por favor inténtelo nuevamente.'
			redirect_back fallback_location: root_path
		end
	end

end
