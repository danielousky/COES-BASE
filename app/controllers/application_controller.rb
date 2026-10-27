class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  # before_action :set_current_process
  before_action :set_paper_trail_whodunnit
  before_action :set_paper_trail_request_info
  before_action :force_password_change!

  rescue_from CanCan::AccessDenied do |_exception|
    flash[:warning] = "No tiene permiso para acceder a esa sección. Si cree que es un error, contacte al administrador."
    redirect_back fallback_location: root_path
  end

  # Los controllers con ActionController::Live (Schools, ExportCsv, AcademicProcesses)
  # corren la acción en otro hilo: el `throw :warden` de Devise al vencer la sesión
  # no alcanza el catch de Warden y sale como UncaughtThrowError (500).
  rescue_from UncaughtThrowError do |exception|
    raise exception unless exception.tag == :warden

    reset_session
    flash[:warning] = "Su sesión ha expirado por inactividad. Por favor, ingrese nuevamente."
    redirect_to main_app.new_user_session_path
  end

  # around_action :set_session_data

  helper_method :logged_as_teacher_or_admin?, :logged_as_teacher?, :logged_as_student?, :logged_as_admin?, :current_admin, :current_teacher, :current_student #, :set_current_course


  def user_for_paper_trail
    current_user ? current_user.id : 'Sistema, consola o no_loggin'  # or whatever
  end

  def info_for_paper_trail
    { ip: request.remote_ip, user_agent: request.user_agent }
  end

  def set_paper_trail_request_info
    return unless PaperTrail::Version.table_exists?
    cols = PaperTrail::Version.column_names
    info = {}
    info[:ip]         = request.remote_ip  if cols.include?('ip')
    info[:user_agent] = request.user_agent if cols.include?('user_agent')
    PaperTrail.request.controller_info = info
  rescue StandardError
    PaperTrail.request.controller_info = {}
  end

  def set_current_process
    @academic_process = AcademicProcess.where(id: session[:academic_process_id]).first
  end

  # def set_session_data
  #   Course.session_academic_process_id = session[:academic_process_id]
  #   yield
  #   Course.session_academic_process_id = nil
  # end

  #AUTHORIZES TO:

  def autho_to action_name, clazz
    current_user&.admin&.authorized_to action_name, clazz
  end


  def models_list
    aux = ActiveRecord::Base.connection.tables-['schema_migrations', 'ar_internal_metadata'].map{|model| model.capitalize.singularize.camelize}
    return aux
  end

  # CURRENT USERS BY TYPE
  def current_admin
    current_user.admin if logged_as_admin?
  end

  def current_student
    current_user.student if logged_as_student?    
  end

  def current_teacher
    current_user.teacher if logged_as_teacher?
  end

  # IS LOGGED BY
  def logged_as_teacher_or_admin?
    logged_as_teacher? or logged_as_admin?
  end

  def logged_as_teacher?
    !current_user.nil? and !current_user.teacher.nil? and session[:rol].eql? 'teacher'
  end

  def logged_as_student?
    # !current_user.nil? and !current_user.student.nil? and session[:rol].eql? 'student'
    (session[:rol].eql? 'student') and current_user&.student
  end

  def logged_as_admin?
    # !current_user.nil? and !current_user.admin.nil? and session[:rol].eql? 'admin'
    current_user&.admin? and session[:rol].eql? 'admin'
  end

  def set_current_env
    if current_admin
      if current_admin.desarrollador? or current_admin.jefe_control_estudio?
        session[:env_type] = 'School'
        session[:env_ids] = School.ids
      else
        session[:env_type] = current_admin.env_auths.map(&:env_authorizable_type).first
        session[:env_ids] = current_admin.env_auths.map(&:env_authorizable_id)
      end
    end
  end



  def set_session_id_if_multirols
    session[:rol] = params[:rol] if (params[:rol] and current_user)
  end 


  def after_sign_in_path_for(resource)
    # session[:academic_process_id] = AcademicProcess.first.id

    if (current_user and !current_user.updated_password?)
      edit_password_user_path(current_user)
    else
      rols = []
      rols << :admin if current_user.admin
      rols << :student if current_user.student
      rols << :teacher if current_user.teacher
      if rols.count > 1
        pages_multirols_path(roles: rols)
      elsif current_user.admin?
        session[:rol] = 'admin'
        rails_admin_path
      elsif current_user.student?
        session[:rol] = 'student'
        student_session_dashboard_path
      elsif current_user.teacher?
        session[:rol] = 'teacher'
        teacher_session_dashboard_path
      else
        flash[:warning] = "No posee un rol asignado. Por favor diríjase a la Administración para cambiar dicha situación"
        root_path 
      end
    end
  end



  # Ojo: los predicados logged_as_...? no sirven como before_action (devuelven true/false y no cortan nada).
  # Para proteger una acción, este filtro o rechazar.
  def require_admin
    rechazar unless logged_as_admin?
  end

  def administra_escuela?(school_id)
    logged_as_admin? and current_admin.schools_auh&.exists?(id: school_id)
  end

  def estudiante_dueno?(grade)
    logged_as_student? and grade&.student_id.eql? current_user.id
  end

  # El titular de la sección, mientras no haya cerrado el acta
  def profesor_califica?(section)
    logged_as_teacher? and section.teacher_id.eql? current_user.id and !section.qualified?
  end

  # Scaffolds que ninguna vista enlaza: los mismos permisos que da RailsAdmin (Ability), ni uno más
  def autorizar_como_en_rails_admin
    accion = {'index' => :read, 'show' => :read, 'new' => :create, 'create' => :create, 'destroy' => :destroy}.fetch(action_name, :update)
    rechazar unless logged_as_admin? and current_ability.can?(accion, controller_name.classify.constantize)
  end

  # Corta la petición: en HTML vuelve atrás con el aviso; en JSON, JS o descargas responde 403
  def rechazar(mensaje = 'No autorizado')
    respond_to do |format|
      format.html do
        flash[:danger] = mensaje
        redirect_back fallback_location: root_path
      end
      format.any { render json: {data: mensaje, type: 'danger', status: 'error', error: mensaje}, status: :forbidden }
    end
  end

  def authenticate_teacher!
    if !logged_as_teacher?
      reset_session
      flash[:danger] = "Debe iniciar sesión como Profesor"  
      redirect_to root_path
    end
  end

  def authenticate_student!
    if !logged_as_student?
      reset_session
      flash[:danger] = "Debe iniciar sesión como Estudiante"  
      redirect_to root_path
    end
  end

  def authenticate_student_or_teacher!
    if !(logged_as_student? or logged_as_teacher?)
      reset_session
      flash[:danger] = "Debe iniciar sesión como Estudiante o Profesor"  
      redirect_to root_path      
    end
  end

  def administrator_filter
		unless session[:administrador_id]
			reset_session
			flash[:danger] = "Debe iniciar sesión como Administrador"  
			redirect_to root_path
			return false
		end
	end

  def log_filter
		unless session[:usuario_ci]
			reset_session
			flash[:danger] = "Debe iniciar sesión"
			redirect_to root_path
			return false
		end
	end

  def force_password_change!
    return unless current_user
    return if current_user.updated_password?
    return if controller_name == 'users' && action_name.in?(%w[edit_password update])
    return if devise_controller?

    flash[:warning] = "Debe cambiar su contraseña antes de continuar."
    redirect_to edit_password_user_path(current_user)
  end

  def authorized_filter
		accion = (!(controller_name.eql? 'secciones') and (action_name.eql? 'show')) ? 'index' : action_name
		funcion = Restringida.where(controlador: controller_name, accion: accion).first

		if funcion and current_usuario and (current_admin and !current_admin.maestros?) and not(current_usuario.autorizado?(controller_name, accion))
			msg = 'No posee los privilegios para ejecutar la acción solicitada'
			respond_to do |format|
				format.html do
					flash[:danger] = msg
					redirect_back fallback_location: index2_secciones_path
				end
				format.json {render json: {data: msg, status: :success, type: :error} }
			end
		end
	end

end
