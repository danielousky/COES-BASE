class SubjectsController < ApplicationController
  before_action :require_admin
  before_action :set_subject, only: %i[ show ]

  # GET /subjects/1 or /subjects/1.json
  def show
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_subject
      # code = params[:id].split(":").first
      # @subject = Subject.find_by(code: code)
      @subject = Subject.find(params[:id])

    end

    # Only allow a list of trusted parameters through.
    def subject_params
      params.require(:subject).permit(:code, :name, :active, :unit_credits, :ordinal, :qualification_type, :modality, :area_id)
    end
end
