class CoursesController < ApplicationController
  before_action :require_admin
  before_action :set_course, only: %i[update]
  before_action :require_administra_escuela
  def create
    begin
      respond_to do |format|
        course = Course.new(course_params)
        if course.save
          new_section = ApplicationController.helpers.button_add_section(course.id)

          # Los interruptores «Ofertar» y «PCI» de la fila: los mismos de la programación
          @course = course
          course_offer, course_offer_as_pci = [1, 2].map do |tipo|
            view_context.render partial: 'academic_processes/active_course_switch', formats: [:html], locals: {tipo: tipo}
          end

          format.json {render json: {data: "¡Curso activado para el período #{course.academic_process.process_name}!", status: :success, new_section: new_section, type: :create, course_offer: course_offer, course_offer_as_pci: course_offer_as_pci} }
        else
          format.json { render json: {data: course.errors, status: :unprocessable_entity} }
        end
      end
      
    rescue StandardError => e
      format.json { render json: {data: e, status: :unprocessable_entity} }
    end
  end

  # def update
  #   begin
  #     respond_to do |format|
  #       course = Course.find_by(course_params)
  #       if course.update!(offer_as_pci: params[:offer_as_pci])
  #         data = course.offer_as_pci? ? "activado" : "desactivado"
  #         format.json {render json: {data: "¡Curso #{data} como PCI para el período #{course.academic_process.process_name}!", status: :success, type: :update} }
  #       else
  #         format.json { render json: {data: course.errors, status: :unprocessable_entity} }
  #       end
  #     end
  #   rescue StandardError => e
  #     format.json { render json: {data: e, status: :unprocessable_entity} }
  #   end
  # end 

  # UPDATE: los interruptores «Ofertar» y «PCI» de la programación (field-update de Stimulus)
  def update
    respond_to do |format|
      if @course.update(course_params)
        format.json { render json: {data: aviso_de_oferta, type: 'success'} }
      else
        format.json { render json: {data: "¡Error al intentar actualizar el valor de la asignatura!", type: 'danger'} }
      end
    end
  end

  # DELETE /courses/1 or /courses/1.json
  def destroy
    begin
      course = Course.find_by(course_params)
      process_name = course.academic_process.process_name

      respond_to do |format|
        if course.destroy
          format.json {render json: {data: "¡Curso desactivado para el período #{process_name}!", status: :success, type: :destroy} }
        else
          format.json {render json: {data: "¡Error al intentar desactivar la asignatura para el período #{process_name}!", status: :unprocessable_entity} }
        end
      end
    rescue StandardError => e
      respond_to do |format|
        format.json {render json: {data: e, status: :unprocessable_entity} }
      end
    end
  end

  private
    # destroy ubica el curso por proceso y asignatura, así que su proceso es el de los params
    def require_administra_escuela
      proceso = @course&.academic_process || AcademicProcess.find_by(id: params.dig(:course, :academic_process_id))
      rechazar unless proceso and administra_escuela?(proceso.school_id)
    end

    # Only allow a list of trusted parameters through.
    def set_course
      @course = Course.find(params[:id])
    end    
    def course_params
      params.require(:course).permit(:academic_process_id, :subject_id, :offer_as_pci, :offer)
    end

    # El aviso del interruptor dice cómo quedó la asignatura, no solo que se guardó
    def aviso_de_oferta
      if @course.saved_change_to_offer_as_pci?
        @course.offer_as_pci? ? '¡Asignatura ofertada como PCI!' : '¡La asignatura ya no se oferta como PCI!'
      else
        @course.offer? ? '¡Asignatura ofertada en la inscripción!' : '¡Asignatura oculta en la inscripción!'
      end
    end
end
