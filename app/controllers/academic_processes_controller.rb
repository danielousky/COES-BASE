class AcademicProcessesController < ApplicationController
  include ActionController::Live
  include Streamable
  before_action :set_academic_process, only: %i[ show edit update destroy clone_sections clean_courses clean_appointments run_regulation massive_confirmation massive_actas_generation massive_actas_generation_async]
  before_action :require_admin, only: %i[ massive_confirmation clean_courses clean_appointments run_regulation ]

  def massive_confirmation
    total = @academic_process.enroll_academic_processes.not_confirmado.with_payment_report
    total_count = total.count
    begin
      total.each {|ins| ins.confirm_with_email}
      flash[:success] = "Se actualizaron #{total_count} inscripciones"
    rescue StandardError => e
      flash[:danger] = "No fue posible completar la operación: #{e}"
    end
    redirect_back fallback_location: '/admin/enroll_academic_process'
  end

  def massive_actas_generation
    sections = @academic_process.sections.qualified
    
    aux = "Total Actas Periodo #{@academic_process.name}.pdf"
    set_streaming_headers(aux, content_type: "application/pdf")
    
    begin
      # Crear un PDF combinado
      combined_pdf = CombinePDF.new
      
      # Generar PDFs y combinarlos
      sections.each_with_index do |section, index|
        begin
          # footer_html = view_context.render template: "/sections/signatures", locals: {teacher: section.teacher&.user&.acte_name}
          # header_html = view_context.render template: "/sections/acta_header", locals: {school: section.school, section: section}
          
          # pdf_data = render_to_string(
          #   delete_temporary_files: true, 
          #   pdf: "acta_#{section.id}", 
          #   template: "sections/acta", 
          #   page_size: 'letter', 
          #   margin: {top: 72, bottom: 68},
          #   locals: {section: section}, 
          #   formats: [:html],
          #   footer: {content: footer_html},
          #   header: {content: header_html}
          # )
          pdf_data = ExportarPdfPrawn.acta_seccion section.id
          # Agregar el PDF al combinado
          combined_pdf << CombinePDF.parse(pdf_data.render)
          
          Rails.logger.info "PDF generado para sección #{section.id} (#{index + 1}/#{sections.count})"
        rescue => e
          Rails.logger.error "Error generando PDF para sección #{section.id}: #{e.message}"
        end
      end
      
      # Enviar el PDF combinado completo
      response.stream.write combined_pdf.to_pdf
      
    rescue StandardError => e
      Rails.logger.error "Error en generación masiva de actas: #{e.message}"
      flash[:danger] = "No se pudo generar el archivo: #{e.message}"
      redirect_back fallback_location: '/admin/academic_process'
    ensure
      response.stream.close
    end
  end

  def massive_actas_generation_async
    # Iniciar el job en background
    MassiveActasGenerationJob.perform_later(@academic_process.id, current_user&.id)
    
    flash[:info] = "La generación de actas ha comenzado en segundo plano. Recibirás una notificación por email cuando esté lista."
    redirect_back fallback_location: '/admin/academic_process'
  end

  def download_actas
    filename = File.basename(params[:filename].to_s)
    file_path = Rails.root.join('tmp', filename)

    unless file_path.to_s.start_with?(Rails.root.join('tmp').to_s)
      flash[:danger] = "Acceso no permitido."
      return redirect_back fallback_location: '/admin/academic_process'
    end

    if File.exist?(file_path)
      send_file file_path,
                filename: filename,
                type: 'application/pdf',
                disposition: 'attachment'
    else
      flash[:danger] = "El archivo solicitado no existe o ha expirado."
      redirect_back fallback_location: '/admin/academic_process'
    end
  end


  # def massive_actas_generation_alt
  #   sections = @academic_process.sections.qualified
  #   pdf = CombinePDF.new
  #   aux = "Actas_secciones_periodo_#{@academic_process.name}.pdf"
  #   response.headers.delete('Content-Length')
  #   response.headers['Cache-Control'] = 'no-cache'
  #   response.headers['Content-Type'] = "pdf/event-stream;charset='utf-8';header=present"
  #   response.headers['X-Accel-Buffering'] = 'no'
  #   response.headers['ETag'] = '0'
  #   response.headers['Last-Modified'] = '0'
  #   response.headers['Content-Disposition'] = "attachment; filename=#{aux}"    

  #   sections.each do |section|
  #     pdf_data = render_to_string pdf: "acta_#{section.number_acta}", template: "sections/acta", locals: {section: section}, formats: [:html], page_size: 'letter', header: {html: {template: '/sections/acta_header', formats: [:html], layout: false, locals: {school: section.school, section: section}}}, footer: {html: {template: '/sections/signatures', formats: [:html], locals: {teacher: section.teacher&.user&.acte_name}}}, margin: {top: 72, bottom: 68}#, dpi: 150
  #     response.stream.write pdf_data
      
  #   end
  # ensure
  #   response.stream.close
  # end


  def clean_appointments
    school = @academic_process.school
    expired_only = params[:scope] == 'expired'

    enrollment_days = EnrollmentDay.where(academic_process_id: school.academic_processes.select(:id))

    ActiveRecord::Base.transaction do
      if expired_only
        today = Time.current.beginning_of_day
        total_days = enrollment_days.expired.delete_all
        total_grades = school.grades.with_appointment_time.where('appointment_time < ?', today).update_all(appointment_time: nil, duration_slot_time: nil)
        scope_label = 'vencidas'
      else
        total_days = enrollment_days.delete_all
        total_grades = school.grades.with_appointment_time.update_all(appointment_time: nil, duration_slot_time: nil)
        scope_label = 'todas'
      end
    end

    if total_days == 0 && total_grades == 0
      flash[:info] = "No se encontraron citas #{scope_label} para limpiar"
    else
      flash[:success] = "Citas #{scope_label} limpiadas: #{total_days} #{'jornada'.pluralize(total_days)} eliminada(s), #{total_grades} #{'cita'.pluralize(total_grades)} de estudiantes limpiada(s)"
    end
    redirect_back fallback_location: "/admin/academic_process/#{@academic_process.id}/enrollment_day"
  end

  def run_regulation
    total_actualizados = 0
    total_error = 0
    @academic_process.school.enrollment_days.each{|ed| ed.destroy}
    @academic_process.enroll_academic_processes.includes(:grade).each do |iep|

      grade = iep.grade
      
      if iep.is_the_last_enroll_of_grade?
        
        iep.update(permanence_status: iep.get_regulation)
        iep.reload
        if grade.update(appointment_time: nil, duration_slot_time: nil, current_permanence_status: iep.permanence_status, efficiency: grade.calculate_efficiency, weighted_average: grade.calculate_weighted_average, simple_average: grade.calculate_average) and iep.update(efficiency: iep.calculate_efficiency, simple_average: iep.calculate_average, weighted_average: iep.calculate_weighted_average)
          total_actualizados += 1
        else
          total_error += 1
        end
      else
        if grade.update(efficiency: grade.calculate_efficiency, weighted_average: grade.calculate_weighted_average, simple_average: grade.calculate_average)
          total_actualizados += 1
        else
          total_error += 1
        end
      end        
    end
    
    flash[:danger] = "#{ total_error} #{'Error'.pluralize(total_error)} en la actualización del estado de reglamento" if total_error > 0 
    flash[:success] = "#{ total_actualizados} #{'inscripción'.pluralize(total_actualizados)} en total actualizados" if total_actualizados > 0
    
    redirect_back fallback_location: "/admin/academic_process/#{params[:id_return]}/enrollment_day"
  end


  # GET /academic_processes or /academic_processes.json
  def index
    @academic_processes = AcademicProcess.all
  end

  # GET /academic_processes/1 or /academic_processes/1.json
  def show
  end

  # GET /academic_processes/new
  def new
    @academic_process = AcademicProcess.new
  end

  # GET /academic_processes/1/edit
  def edit
  end

  # def change_process_session
  #   session[:academic_process_id] = params[:id]
  #   redirect_back fallback_location: root_path
  # end

  def clean_courses
    total = @academic_process.courses.count
    if @academic_process.courses.destroy_all
      flash[:info] = "Eliminados #{total} cursos con sus respectivas secciones."
    else
      flash[:danger] = "No se pudieron eliminar los cursos."
    end

    redirect_back fallback_location: root_path
  end

  def clone_sections
    if @academic_process.enroll_academic_processes.any?
      flash[:denger] = 'No se puede clonar un processo con registro académicos. Primero limpie el proceso académico y luego procesa a clonarlo.'
    else
      cloneble_academic_process = AcademicProcess.find params[:cloneble_academic_process_id]
      errors = 0
      completed = 0

      @academic_process.courses.destroy_all
      begin
        cloneble_academic_process.courses.includes(sections: { timetable: :timeblocks }).each do |course|
          nuevo_curso = course.dup
          nuevo_curso.academic_process_id = @academic_process.id
          if nuevo_curso.save
            course.sections.each do |section|
              nueva_seccion = section.dup
              nueva_seccion.course_id = nuevo_curso.id
              nueva_seccion.teacher_id = nil unless params[:teachers]
              nueva_seccion.qualified = false
              if nueva_seccion.save

                  if params[:schedules] and section.timetable
                    tt_aux = section.timetable.dup
                    tt_aux.section_id = nueva_seccion.id
                    if tt_aux.save(validate: false)
                      p "  tt_aux.id: #{tt_aux.id}  ".center(10000, '*')
                      section.timetable.timeblocks.each do |tb|
                        tb_aux = tb.dup
                        tb_aux.timetable_id = tt_aux.id
                        tb_aux.save
                      end
                    end
                  end

                completed +=1
              else
                errors += 1
              end
            end
          else
            errors += 1
          end
        end
      rescue StandardError => e
        flash[:danger] = e
      end  
      flash[:danger] = "#{errors} Cargas con errores. Vuelva a intentarlo." if errors > 0
      if completed > 0
        flash[:success] = "Clonación de #{completed} secciones." 
        flash[:success] += " Incluida clonación de Inscrucciones de Inscripción" if @academic_process.update(enroll_instructions: cloneble_academic_process.enroll_instructions)
      end

    end

    redirect_back fallback_location: root_path

  end



  # POST /academic_processes or /academic_processes.json
  def create
    @academic_process = AcademicProcess.new(academic_process_params)

    respond_to do |format|
      if @academic_process.save
        format.html { redirect_to academic_process_url(@academic_process), notice: "Academic process was successfully created." }
        format.json { render :show, status: :created, location: @academic_process }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @academic_process.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /academic_processes/1 or /academic_processes/1.json
  def update
    respond_to do |format|
      if @academic_process.update(academic_process_params)
        # format.json { render json: '¡Escuela actualizada con éxito!', status: :ok}
        format.json {render json: {data: '¡Período actualizado con éxito!', status: :success} }
        format.html { redirect_back fallback_location: root_path, notice: '¡Período actualizado con Éxito!' }
      else
        format.json { render json: {data: @school.errors, status: :unprocessable_entity} }
        format.html { redirect_back fallback_location: root_path, notice: 'No fue posible realizar la solicitud!'  }
      end
    end
  end

  # DELETE /academic_processes/1 or /academic_processes/1.json
  def destroy
    @academic_process.destroy

    respond_to do |format|
      format.html { redirect_to academic_processes_url, notice: "Academic process was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  # GET /academic_processes/get_school_processes
  def get_school_processes
    school_id = params[:school_id]
    
    if school_id.present?
      school = School.find(school_id)
      processes = school.academic_processes.order(created_at: :desc)
      
      processes_data = processes.map do |process|
        {
          id: process.id,
          period_desc_and_modality: process.period_desc_and_modality
        }
      end
      
      render json: { processes: processes_data }
    else
      render json: { processes: [] }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_academic_process
      @academic_process = AcademicProcess.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def academic_process_params
      params.require(:academic_process).permit(:school_id, :period_id, :max_credits, :max_subjects, :active, :enroll, :post_qualification, :payments_active)
    end
end
