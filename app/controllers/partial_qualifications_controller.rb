class PartialQualificationsController < ApplicationController
  before_action :set_academic_record, only: %i[ update ]
  before_action :logged_as_teacher_or_admin?, only: %i[ update ]

  # PATCH/PUT /academic_records/1 or /academic_records/1.json
  def update
    respond_to do |format|
      begin
        if partial_qualification_params[:value].eql? '-2'
          if @academic_record.partial_qualifications.find_by(partial: partial_qualification_params[:partial])&.destroy
            format.js { render json: {data: '¡Datos Guardados con éxito!', type: 'success'}, status: :ok}
          else
            format.js { render json: {data: "Error: #{@academic_record.errors.full_messages.to_sentence}", type: 'danger'}, status: :ok }
          end
        else
          qua = @academic_record.partial_qualifications.find_or_initialize_by(partial: partial_qualification_params[:partial])
          qua.value = partial_qualification_params[:value].to_f
          if qua.save
            @academic_record.reload
            format.js { render json: {data: '¡Datos Guardados con éxito!', type: 'success', final: @academic_record.final_q_to_02i}, status: :ok}
          else
            format.js { render json: {data: "Error: #{qua.errors.full_messages.to_sentence}", type: 'danger'}, status: 500, error:  "Error: #{qua.errors.full_messages.to_sentence}"}
          end
        end
      rescue StandardError => e
        format.js { render json: {data: "Error: #{e}", type: 'danger'}, status: 500, error:  "Error: #{e}"}
      end
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_academic_record
      @academic_record = AcademicRecord.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def partial_qualification_params
      params.require(:partial_qualification).permit(:partial, :value)
    end
end
