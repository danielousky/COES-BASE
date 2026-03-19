class PaymentReportsController < ApplicationController
  before_action :set_payment_report, only: %i[ show edit update destroy quick_validation]

  # GET /payment_reports or /payment_reports.json
  def index
    @payment_reports = PaymentReport.all
  end

  # GET /payment_reports/1 or /payment_reports/1.json
  def show
  end

  # GET /payment_reports/new
  def new
    @payment_report = PaymentReport.new
  end

  # GET /payment_reports/1/edit
  def edit
  end

  # POST /payment_reports or /payment_reports.json
  def create
    @payment_report = PaymentReport.new(payment_report_params)

    if @payment_report.save
      flash[:success] = "¡Reporte de pago realizado con éxito! Por favor espere la confirmación por parte de Control de Estudio."
    else
      flash[:danger] = @payment_report.errors.full_messages.to_sentence
    end

    redirect_back fallback_location: root_path

  end

  # PATCH/PUT /payment_reports/1 or /payment_reports/1.json
  # def update
    
  #   if @payment_report.update(payment_report_params)
  #     flash[:success] = "Payment report was successfully updated."

  #     # format.html { redirect_to payment_report_url(@payment_report), notice: "Payment report was successfully updated." }
  #     # format.json { render :show, status: :ok, location: @payment_report }
  #   else
  #     flash[:danger] = @payment_report.errors.full_messages.to_sentence
  #     # format.html { render :edit, status: :unprocessable_entity }
  #     # format.json { render json: @payment_report.errors, status: :unprocessable_entity }
  #   end

  #   redirect_back fallback_location: root_path

  # end

  def quick_validation
    unless logged_as_admin?
      flash[:danger] = 'No autorizado'
      return redirect_back fallback_location: root_path
    end

    if @payment_report.update(payment_report_params)
      flash[:success] = "¡Reporte de pago actualizado!"

      # format.html { redirect_to payment_report_url(@payment_report), notice: "Payment report was successfully updated." }
      # format.json { render :show, status: :ok, location: @payment_report }
    else
      flash[:danger] = @payment_report.errors.full_messages.to_sentence
      # format.html { render :edit, status: :unprocessable_entity }
      # format.json { render json: @payment_report.errors, status: :unprocessable_entity }
    end

    redirect_back fallback_location: root_path

  end

  # DELETE /payment_reports/1 or /payment_reports/1.json
  def destroy
    unless logged_as_admin?
      flash[:danger] = 'No autorizado'
      return redirect_back fallback_location: root_path
    end

    @payment_report.destroy

    respond_to do |format|
      format.html { redirect_to payment_reports_url, notice: "Payment report was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_payment_report
      @payment_report = PaymentReport.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def payment_report_params
      params.require(:payment_report).permit(:amount, :transaction_id, :transaction_type, :transaction_date, :origin_bank_id, :payable_id, :payable_type, :receiving_bank_account_id, :voucher, :owner_account_ci, :owner_account_name, :status )
    end
end
