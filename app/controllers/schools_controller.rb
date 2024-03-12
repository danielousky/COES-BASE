class SchoolsController < ApplicationController
  before_action :logged_as_admin?
  before_action :set_school, only: %i[ show edit update destroy export_grades export_grades_stream]

  def export_grades
    respond_to do |format|
      format.xls {send_data @school.all_grades_to_csv, filename: "#{@school.short_name}_todos.xls"}
    end
  end


  def export_grades_stream
    respond_to do |format|
      format.xls do
        begin          
          response.headers.delete('Content-Length')
          response.headers['Cache-Control'] = 'no-cache'
          response.headers['X-Accel-Buffering'] = 'no'
          response.headers['Content-Type'] = 'text/event-stream'
          response.headers['ETag'] = '0'
          response.headers['Last-Modified'] = '0'
          response.headers['Content-Disposition'] = "attachment; filename=#{@school.short_name}_todos_stream.xls"

          response.stream.write @school.all_grades_to_csv
        ensure
          response.stream.close
        end
      end
    end
  end  


  # GET /schools or /schools.json
  def index
    @schools = School.all
  end

  # GET /schools/1 or /schools/1.json
  def show
  end

  # GET /schools/new
  def new
    @school = School.new
  end

  # GET /schools/1/edit
  def edit
  end

  # POST /schools or /schools.json
  def create
    @school = School.new(school_params)

    respond_to do |format|
      if @school.save
        format.html { redirect_to school_url(@school), notice: "School was successfully created." }
        format.json { render :show, status: :created, location: @school }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @school.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /schools/1 or /schools/1.json
  def update

    params[:school][:enroll_process_id] = nil if params[:school][:enroll_process_id].eql? '-1'
    params[:school][:active_process_id] = nil if params[:school][:active_process_id].eql? '-1'
    respond_to do |format|
      if @school.update(school_params)
        # format.json { render json: '¡Escuela actualizada con éxito!', status: :ok}
        # format.html { redirect_back fallback_location root_path }
        format.json {render json: {data: '¡Escuela actualizada con éxito!', status: :success} }
      else
        format.json { render json: {data: @school.errors, status: :unprocessable_entity} }
      end
    end
  end

  # DELETE /schools/1 or /schools/1.json
  def destroy
    @school.destroy

    respond_to do |format|
      format.html { redirect_to schools_url, notice: "School was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_school
      @school = School.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def school_params
      params.require(:school).permit(:code, :name, :enable_subject_retreat, :enable_change_course, :enable_dependents, :period_id, :enroll_process_id, :active_process_id, :enable_enroll_payment_report, :enable_by_level)
    end
end
