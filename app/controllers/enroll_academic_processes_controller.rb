class EnrollAcademicProcessesController < ApplicationController
  before_action :set_enroll_academic_process, only: %i[ show edit update destroy study_constance total_retire update_permanece_status preinscribir_admin]
  before_action :require_admin, only: %i[ total_retire update_permanece_status preinscribir_admin ]

  # GET /enroll_academic_processes or /enroll_academic_processes.json
  def index
    @enroll_academic_processes = EnrollAcademicProcess.includes(:academic_process, grade: [:study_plan, { student: :user }])
  end

  # GET /enroll_academic_processes/1 or /enroll_academic_processes/1.json

  def show
    if @enroll_academic_process.confirmado? and (@enroll_academic_process.academic_process.enroll? or @enroll_academic_process.academic_process.active?)

      @school = @enroll_academic_process.school
      @faculty = @school.faculty
      @user = @enroll_academic_process.user
      @academic_process = @enroll_academic_process.academic_process
      @academic_records = @enroll_academic_process.academic_records.section_not_equivalencias
      event = 'Se generó Constancia de Inscripción'
      file_name = "ConstanciaInscripcion#{@enroll_academic_process.short_name}"
      @title = 'CONSTANCIA DE INSCRIPCIÓN'
      if params[:study]
        file_name = "ConstanciaEstudio#{@enroll_academic_process.short_name}"
        event = 'Se generó Constancia de Estudio'
        @title = 'CONSTANCIA DE ESTUDIO'
        @study_contance = true
      end
      respond_to do |format|
        format.html
        format.pdf do
          @version = @enroll_academic_process.versions.create(event: event)

          # salt  = SecureRandom.random_bytes(32)
          # key   = ActiveSupport::KeyGenerator.new('password').generate_key(salt, 32) 
          # crypt = ActiveSupport::MessageEncryptor.new(key)

          # @encrypted_id, @salt = crypt.encrypt_and_sign(@version.id).split("/")


          render pdf: file_name, template: "enroll_academic_processes/constance", formats: [:html], page_size: 'letter', backgroud: true,  footer: { center: 'Página: [page] de [topage]', font_size: '8'}
        end
      end

    else
      flash[:warning] = 'Debe estar confirmada la inscripción y activado el período de inscripción para descargar el documento solicitado.'
      redirect_back fallback_location: '/admin'
    end
  end


  # GET /enroll_academic_processes/new
  def new
    @enroll_academic_process = EnrollAcademicProcess.new
  end

  # GET /enroll_academic_processes/1/edit
  def edit
  end

  def reserve_space
    # La lógica de negocio (liberar/reservar cupo, reglas y transacción ACID con
    # lock) vive en el modelo: EnrollAcademicProcess.reservar_cupo.
    resultado = EnrollAcademicProcess.reservar_cupo(
      grade_id:            params[:grade_id],
      academic_process_id: params[:academic_process_id],
      section_id:          params[:section_id],
      course_id:           params[:course_id]
    )
    cupo = resultado.section ? resultado.section.description_with_quotes : 'Seleccione sección o libere cupo'
    respond_to do |format|
      format.json do
        render json: { data: resultado.mensaje, status: resultado.estado, cupo: cupo }
      end
    end
  end

  def enroll
    enroll_academic_process = EnrollAcademicProcess.where(grade_id: params[:grade_id], academic_process_id: params[:academic_process_id]).first
    any_error = false
    if enroll_academic_process.nil?
      flash[:danger] = 'No realizó inscripción alguna. Por favor, selección las asignaturas e inténtelo nuevamente. Tenga en cuenta que al seleccionar una sección en cada asignatura, debe aparecer un mensaje afirmativo de completación de la reserva del cupo.'
    elsif !(enroll_academic_process.academic_records.any?)
      flash[:danger] = 'Sin selección se asignaturas. Por favor, selección alguna asignaturas e inténtelo nuevamente. Tenga en cuenta que al seleccionar una sección en cada asignatura, debe aparecer un mensaje afirmativo de completación de la reserva del cupo.'
      any_error = true
    elsif (enroll_academic_process.total_credits > enroll_academic_process.academic_process.max_credits)
      flash[:danger] = "Supera el límite de créditos permitidos para este proceso de inscripción. Por favor, corrija su selección e inténtelo de nuevo. Se anularon las selecciones hechas con anteridad."
      any_error = true
    elsif (enroll_academic_process.total_subjects > enroll_academic_process.academic_process.max_subjects)
      flash[:danger] = "Supera el límite de asignaturas permitidas para este proceso de inscripción. Por favor, corrija su inscripción e inténtelo de nuevo. Se anularon las selecciones previas."
      
      any_error = true
    elsif params[:enroll_status]
      if enroll_academic_process.update(enroll_status: params[:enroll_status])
        flash[:success] = "¡#{enroll_academic_process.enroll_status&.titleize} con éxito!"
        if params[:send_confirmation]
          begin
            if enroll_academic_process.preinscrito?
              flash[:info] = '¡Correo de Preinscripción Enviado!' if StudentMailer.preinscrito(enroll_academic_process).deliver_now
            else
              flash[:info] = '¡Correo de Confirmación Enviado!' if UserMailer.enroll_confirmation(enroll_academic_process.id).deliver_now
            end
          rescue StandardError => e
            flash[:warning] = "Correo de completación de proceso de preinscripción no enviado: #{e}" 
          end
        end
      else
        flash[:danger] = "Error: #{enroll_academic_process.errors.full_messages.to_sentence}"
      end
    elsif (enroll_academic_process.update(enroll_status: :preinscrito))
      # info_bitacora "Estudiante #{enroll_academic_process.estudiante_id} Preinscrito en el periodo #{enroll_academic_process.periodo.id} en #{enroll_academic_process.escuela.descripcion}.", Bitacora::CREACION, enroll_academic_process
      begin
        # info_bitacora "Envío de correo de Preinscripcion #{enroll_academic_process.estudiante_id} Preinscrito en el periodo #{enroll_academic_process.periodo.id} en #{enroll_academic_process.escuela.descripcion}.", Bitacora::CREACION, enroll_academic_process if EstudianteMailer.preinscrito(enroll_academic_process.estudiante.usuario, enroll_academic_process).deliver

        StudentMailer.preinscrito(enroll_academic_process).deliver
        
      rescue StandardError => e
        flash[:warning] = "Correo de completación de proceso de preinscripción no enviado: #{e}" 
      end
      flash[:success] = "Proceso de preinscripción completado con éxito. Un correo con el resumen del proceso le ha sido enviado."

      flash[:info] = "Asignaturas Inscritas: #{enroll_academic_process.total_subjects}. Créditos Inscritos: #{enroll_academic_process.total_credits}"
    else
      flash[:danger] = "Error al intentar completar el procesos de preinscripción: #{enroll_academic_process.errors.full_messages.to_sentence}"
      any_error = true
    end
    enroll_academic_process.destroy if any_error

    if session[:rol].eql? 'admin'
      redirect_to "/admin/student/#{enroll_academic_process.student.id}"
    else
      redirect_to '/student_session/dashboard'
    end
  end

  # POST /enroll_academic_processes?academic_process_id=x&grade_id=y
  def create
    if grade = Grade.find(params[:grade_id]) and academic_process = AcademicProcess.find(params[:academic_process_id])
      school = grade.school

      permanence_status = !(grade.enroll_academic_processes.any?) ? :nuevo : :regular
      @enroll_academic_process = EnrollAcademicProcess.new(grade_id: grade.id, academic_process_id: academic_process.id, permanence_status: permanence_status)
      @enroll_academic_process.enroll_status = @enroll_academic_process.historical? ?
      :preinscrito : :reservado
      if @enroll_academic_process.save!
        flash[:success] = 'Proceso de Inscripción Iniciado'
        redirect_to "/admin/enroll_academic_process/#{@enroll_academic_process.id}"
      else
        flash[:danger] = @enroll_academic_process.errors.full_messages.to_sentence
        redirect_back fallback_location: '/admin'
      end


    else
      flash[:danger] = 'Grado o Periodo no encontrado'
      redirect_back fallback_location: '/admin'
    end
  end

  def total_retire
    @enroll_academic_process.academic_records.find_each { |ar| ar.update!(status: :retirado) }
    flash[:info] = '¡Actualización Exitosa!'
  rescue StandardError => e
    flash[:danger] = "Error al retirar: #{e.message}"
  ensure
    redirect_back fallback_location: "/admin/student/#{@enroll_academic_process.student.id}"
  end

  def update_permanece_status
    if @enroll_academic_process.update(enroll_academic_process_params)
      flash[:success] = 'Actualizado el estado de permanecia del Estudiante'
    else
      flash[:danger] = @enroll_academic_process.errors.full_messages.to_sentence
    end
    redirect_back fallback_location: '/admin/student'
  end

  # PATCH/PUT /enroll_academic_processes/1 or /enroll_academic_processes/1.json
  def preinscribir_admin
    if @enroll_academic_process.update(enroll_status: params[:enroll_status])
      flash[:success] = "¡#{@enroll_academic_process.enroll_status&.titleize} con éxito!"
      if params[:send_confirmation]
        begin
        # info_bitacora "Envío de correo de Preinscripcion #{enroll_academic_process.estudiante_id} Preinscrito en el periodo #{enroll_academic_process.periodo.id} en #{enroll_academic_process.escuela.descripcion}.", Bitacora::CREACION, enroll_academic_process if EstudianteMailer.preinscrito(enroll_academic_process.estudiante.usuario, enroll_academic_process).deliver
          if @enroll_academic_process.preinscrito?
            flash[:info] = '¡Correo de Preinscripción Enviado!' if StudentMailer.preinscrito(@enroll_academic_process).deliver_now
          else
            flash[:info] = '¡Correo de Confirmación Enviado!' if UserMailer.enroll_confirmation(@enroll_academic_process.id).deliver_now
          end
        rescue StandardError => e
          flash[:warning] = "Correo de completación de proceso de preinscripción no enviado: #{e}" 
        end
      end
    else
      flash[:danger] = "Error: #{@enroll_academic_process.errors.full_messages.to_sentence}"
    end
    redirect_back fallback_location: "/admin/student"
  end

  def update
    respond_to do |format|
      send_confirmation = (params['enroll_academic_process'] and params['enroll_academic_process']['enroll_status'] and params['enroll_academic_process']['enroll_status'].eql? 'confirmado') ? true : false
      if @enroll_academic_process.update(enroll_academic_process_params)
        flash[:success] = "Inscripción en Proceso Académico #{@enroll_academic_process.academic_process.process_name} Actualizada"

        begin
          flash[:info] = 'Se envió un correo al estudiante con la información.' if send_confirmation and UserMailer.enroll_confirmation(@enroll_academic_process.id).deliver_now
          
        rescue StandardError => e
          flash[:warning] = "No se pudo enviar el correo: #{e}"
        end

        format.html { redirect_back fallback_location: enroll_academic_process_url(@enroll_academic_process) }
        format.json { render :show, status: :ok, location: @enroll_academic_process }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @enroll_academic_process.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /enroll_academic_processes/1 or /enroll_academic_processes/1.json
  def destroy
    @enroll_academic_process.destroy

    respond_to do |format|      
      format.html { redirect_to "/admin/student/#{@enroll_academic_process.student.id}", notice: "¡Inscripción en Proceso Académico eliminada con éxito!" }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_enroll_academic_process
      @enroll_academic_process = EnrollAcademicProcess.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def enroll_academic_process_params
      params.require(:enroll_academic_process).permit(:grade_id, :academic_process_id, :enroll_status, :permanence_status)
    end
end
