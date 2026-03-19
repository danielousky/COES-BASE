class CoursesController < ApplicationController
  before_action :set_course, only: %i[update]
  def create
    begin
      respond_to do |format|
        course = Course.new(course_params)
        if course.save
          new_section = ApplicationController.helpers.button_add_section(course.id)

          # Ofertar
          title = 'Ofertar u ocultar asignatura durante la inscripción de los estudiantes' 
          name = "course_offer_#{course.id}"
          js_action_name = 'courseOffer(this);'

          course_offer = view_context.render partial: 'layouts/switch_checkbox_layout', locals: {title: title, name: name, id: course.id, checked: course&.offer?, disabled: false, js_action_name: js_action_name}

          # Ofertar como PCI
          title = 'Ofertar u ocultar asignatura como PCI durante la inscripción de los estudiantes' 
          name = "course_offer_as_pci#{course.id}"
          js_action_name = 'courseOffer(this, true);'

          course_offer_as_pci = view_context.render partial: 'layouts/switch_checkbox_layout', locals: {title: title, name: name, id: course.id, checked: course&.offer_as_pci?, disabled: false, js_action_name: js_action_name}

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

  # UPDATE
  def update
    respond_to do |format|
      if @course.update(course_params)
        msg = "¡Valor actualizado!"
        format.json { render json: {data: msg, status: :success} }
      else
        format.json {render json: {data: "¡Error al intentar actualizar el valor de la asignatura!", status: :unprocessable_entity} }
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
    # Only allow a list of trusted parameters through.
    def set_course
      @course = Course.find(params[:id])
    end    
    def course_params
      params.require(:course).permit(:academic_process_id, :subject_id, :offer_as_pci, :offer)
    end
end
