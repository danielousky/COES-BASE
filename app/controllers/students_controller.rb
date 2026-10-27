class StudentsController < ApplicationController
  before_action :set_student, only: [:show, :edit, :update]
  before_action :authenticate_student_or_teacher!
  # Sus propios datos: antes bastaba cambiar el id para ver o editar los de otro estudiante
  before_action -> { rechazar unless logged_as_student? and @student.id.eql? current_user.id }, only: [:show, :edit, :update]

  # def edit
  # end
  layout 'logged'


  def update
    if @student.update(student_params)
      flash[:success] = '¡Datos guardados con éxito!'
    else
      flash[:danger] = "Error al intentar guardar los datos: #{@student.errors.full_messages.to_sentence}"
    end
    # back = root_path
    # back = teacher_session_dashboard_path if logged_as_teacher?
    # back = student_session_dashboard_path if logged_as_student?

    redirect_to student_session_dashboard_path

  end

  def countries
    country = params[:term]
    data_hash = Student.countries
    render json: data_hash[country].sort{|a,b| a <=> b}, status: :ok
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_student
      @student = Student.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def student_params
      params.require(:student).permit(:disability, :nacionality, :marital_status, :origin_country, :origin_city, :birth_date, :grade_title, :grade_university, :graduate_year )
    end

end
