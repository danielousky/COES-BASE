class StudyPlansController < ApplicationController
  before_action :set_study_plan, only: %i[ show edit update destroy save_requirement_by_level oferta_estudiante]

  # GET /study_plans/1/oferta_estudiante.json?ci=  (mapa de prelaciones, modo "Ver como estudiante")
  def oferta_estudiante
    unless logged_as_admin? and current_admin.schools_auh&.exists?(id: @study_plan.school_id)
      return render json: {error: 'No autorizado'}, status: :forbidden
    end

    ci = params[:ci].to_s.strip
    grade = Grade.joins(:study_plan, student: :user).where('study_plans.school_id': @study_plan.school_id, 'users.ci': ci).order(id: :desc).first
    return render json: {error: estudiante_fuera_del_plan(ci)}, status: :not_found unless grade

    render json: MapaPrelaciones.new(@study_plan.school).oferta(grade)
  end

  # GET /study_plans or /study_plans.json
  def save_requirement_by_level
    error = []
    params[:requirement_by_levels].each do |rbl|
      rbl_aux = @study_plan.requirement_by_levels.find_or_initialize_by(level: rbl[:level], subject_type_id: rbl[:subject_type_id])
      rbl_aux.required_subjects = rbl[:required_subjects]
      if !(rbl_aux.save)
        p "     ERRROR: #{rbl_aux.errors.full_messages.to_sentence}     ".center(2000, '#')
        error << rbl_aux.errors.full_messages.to_sentence
      end
    end
    if error.any? 
      flash[:danger] = "#{error.count} errores al intentar guardar el formulario. Por favor, inténtelo de nuevo"
    else 
      flash[:success] = '¡Requerimientos guardado con éxito!'
    end
    redirect_to "/admin/study_plan/#{@study_plan.id}/structure"
  end


  def index
    @study_plans = StudyPlan.all
  end

  # GET /study_plans/1 or /study_plans/1.json
  def show
  end

  # GET /study_plans/new
  def new
    @study_plan = StudyPlan.new
  end

  # GET /study_plans/1/edit
  def edit
  end

  # POST /study_plans or /study_plans.json
  def create
    @study_plan = StudyPlan.new(study_plan_params)

    respond_to do |format|
      if @study_plan.save
        format.html { redirect_to study_plan_url(@study_plan), notice: "Study plan was successfully created." }
        format.json { render :show, status: :created, location: @study_plan }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @study_plan.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /study_plans/1 or /study_plans/1.json
  def update
    respond_to do |format|
      if @study_plan.update(study_plan_params)
        format.html { redirect_to study_plan_url(@study_plan), notice: "Study plan was successfully updated." }
        format.json { render :show, status: :ok, location: @study_plan }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @study_plan.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /study_plans/1 or /study_plans/1.json
  def destroy
    @study_plan.destroy

    respond_to do |format|
      format.html { redirect_to study_plans_url, notice: "Study plan was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Si la cédula es de otra escuela, se dice cuál; el nombre sólo si el admin también administra esa escuela
    def estudiante_fuera_del_plan(ci)
      otro = Grade.joins(student: :user).where('users.ci': ci).order(id: :desc).first
      return "No hay un estudiante con cédula #{ci}" unless otro

      quien = current_admin.schools_auh.exists?(id: otro.school.id) ? "#{otro.student.user.reverse_name} (#{ci})" : "La cédula #{ci}"
      "#{quien} es de #{otro.school.name}, plan #{otro.study_plan.code}: búscalo en el mapa de ese plan"
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_study_plan
      @study_plan = StudyPlan.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def study_plan_params
      params.require(:study_plan).permit(:code, :name, :school_id)
    end
end
