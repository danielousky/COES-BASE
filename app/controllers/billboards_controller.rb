class BillboardsController < ApplicationController
  before_action :require_admin
  before_action :set_billboard, only: [:show, :edit, :update, :destroy, :set_active, :set_content]


  # GET /billboards or # GET /billboards.json
  def set_active
    @billboard.active = !@billboard.active
    if @billboard.save
      aux = @billboard.activa ? 'Cartelera Activada' : 'Cartelera Desactivada'
      render json: {data: aux, status: :success}
    else
      render json: {data: "Error al intentar cambiar la noticia : #{@comentario.errors.messages.to_sentence()}", status: :success}
    end

  end


  # GET /billboards or /billboards.json
  def index
    @title = "Cartelera"
    @billboards = Billboard.all
  end

  # GET /billboards/1 or /billboards/1.json
  def show
    @title = "Vista previa de la Cartelera"
  end

  # GET /billboards/new
  def new
    @title = "Nueva Cartelera"
    @billboard = Billboard.new
  end

  # GET /billboards/1/edit
  def edit
    @title = "Editando Cartelera"
  end

  # POST /billboards or /billboards.json
  def create
    @billboard = Billboard.new(billboard_params)

    respond_to do |format|
      if @billboard.save
        format.html { redirect_to billboard_url(@billboard), notice: "Cartelera creada con éxito." }
        format.json { render :show, status: :created, location: @billboard }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @billboard.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /billboards/1 or /billboards/1.json
  def update
    respond_to do |format|
      if @billboard.update(billboard_params)
        format.html { redirect_to billboard_url(@billboard), notice: "Billboard was successfully updated." }
        format.json { render :show, status: :ok, location: @billboard }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @billboard.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /billboards/1 or /billboards/1.json
  def destroy
    @billboard.destroy

    respond_to do |format|
      format.html { redirect_to billboards_url, notice: 'Cartelera eliminada con éxito.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_billboard
      @billboard = Billboard.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def billboard_params
      params.require(:billboard).permit(:active, :content)
    end
end
