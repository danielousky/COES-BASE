class CoursesController < ApplicationController

  def create
    begin
      respond_to do |format|
        course = Course.new(course_params)
        if course.save
          new_section = ApplicationController.helpers.button_add_section(course.id)
          # p "   CURSO: <#{new_section}>.   ".center(500, "#")
          format.json {render json: {data: "¡Curso activado para el período #{course.academic_process.period_name}!", status: :success, new_section: new_section, type: :create} }
        else
          format.json { render json: {data: course.errors, status: :unprocessable_entity} }
        end
      end
      
    rescue Exception => e
      format.json { render json: {data: e, status: :unprocessable_entity} }
    end
  end

  def update
    begin
      respond_to do |format|
        course = Course.find_by(course_params)
        if course.update!(offer_as_pci: params[:offer_as_pci])
          data = course.offer_as_pci? ? "activado" : "desactivado"
          format.json {render json: {data: "¡Curso #{data} como PCI para el período #{course.academic_process.period_name}!", status: :success, type: :update} }
        else
          format.json { render json: {data: course.errors, status: :unprocessable_entity} }
        end
      end
    rescue Exception => e
      format.json { render json: {data: e, status: :unprocessable_entity} }
    end
  end 

  # DELETE /courses/1 or /courses/1.json
  def destroy
    begin
      course = Course.find_by(course_params)
      period_name = course.academic_process.period_name

      respond_to do |format|
        if course.destroy
          format.json {render json: {data: "¡Curso desactivado para el período #{period_name}!", status: :success, type: :destroy} }
        else
          format.json {render json: {data: "¡Error al intentar desactivar la asignatura para el período #{period_name}!", status: :unprocessable_entity} }
        end
      end
    rescue Exception => e
      respond_to do |format|
        format.json {render json: {data: e, status: :unprocessable_entity} }
      end
    end
  end

  private
    # Only allow a list of trusted parameters through.
    def course_params
      params.require(:course).permit(:academic_process_id, :subject_id, :offer_as_pci)
    end
end
