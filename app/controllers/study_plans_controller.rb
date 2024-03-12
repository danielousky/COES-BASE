class StudyPlansController < ApplicationController
  before_action :set_study_plan, only: %i[ show edit update destroy save_requirement_by_level]

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
    # Use callbacks to share common setup or constraints between actions.
    def set_study_plan
      @study_plan = StudyPlan.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def study_plan_params
      params.require(:study_plan).permit(:code, :name, :school_id)
    end
end
