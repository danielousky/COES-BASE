class PeriodTypesController < ApplicationController
  before_action :autorizar_como_en_rails_admin
  before_action :set_period_type, only: %i[ show edit update destroy ]

  # GET /period_types or /period_types.json
  def index
    @period_types = PeriodType.all
  end

  # GET /period_types/1 or /period_types/1.json
  def show
  end

  # GET /period_types/new
  def new
    @period_type = PeriodType.new
  end

  # GET /period_types/1/edit
  def edit
  end

  # POST /period_types or /period_types.json
  def create
    @period_type = PeriodType.new(period_type_params)

    respond_to do |format|
      if @period_type.save
        format.html { redirect_to period_type_url(@period_type), notice: "Period type was successfully created." }
        format.json { render :show, status: :created, location: @period_type }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @period_type.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /period_types/1 or /period_types/1.json
  def update
    respond_to do |format|
      if @period_type.update(period_type_params)
        format.html { redirect_to period_type_url(@period_type), notice: "Period type was successfully updated." }
        format.json { render :show, status: :ok, location: @period_type }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @period_type.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /period_types/1 or /period_types/1.json
  def destroy
    @period_type.destroy

    respond_to do |format|
      format.html { redirect_to period_types_url, notice: "Period type was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_period_type
      @period_type = PeriodType.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def period_type_params
      params.require(:period_type).permit(:code, :name)
    end
end
