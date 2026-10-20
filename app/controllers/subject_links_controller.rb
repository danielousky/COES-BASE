class SubjectLinksController < ApplicationController
  before_action :set_subject_link, only: %i[ destroy invertir ]
  before_action :autorizar_cambio!

  # POST /subject_links.json  {subject_link: {prelate_subject_id, depend_subject_id}, confirmar: '1'}
  def create
    guardar SubjectLink.new(params.require(:subject_link).permit(:prelate_subject_id, :depend_subject_id))
  end

  # PATCH /subject_links/1/invertir.json
  def invertir
    @subject_link.prelate_subject_id, @subject_link.depend_subject_id = @subject_link.depend_subject_id, @subject_link.prelate_subject_id
    guardar @subject_link
  end

  # DELETE /subjectlinks/1 or /subject_links/1.json
  def destroy
    @subject_link.destroy

    respond_to do |format|
      format.html { redirect_back fallback_location: rails_admin_path, notice: 'Prelación eliminada' }
      format.json { render json: {id: @subject_link.id} }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_subject_link
      @subject_link = SubjectLink.find(params[:id])
    end

    # Si la prelación parece al revés se devuelve la advertencia y sólo se guarda al reenviarla con confirmar
    def guardar(link)
      if link.valid? and (aviso = link.advertencia) and params[:confirmar] != '1'
        render json: {advertencia: aviso, requiere_confirmacion: true}, status: :conflict
      elsif link.save
        render json: link.datos_mapa
      else
        render json: {error: link.errors.full_messages.to_sentence}, status: :unprocessable_entity
      end
    end

    def autorizar_cambio!
      permiso = action_name == 'destroy' ? 'delete' : 'update'
      materia = @subject_link&.prelate_subject || Subject.find_by(id: params.dig(:subject_link, :prelate_subject_id))
      autorizado = logged_as_admin? && current_admin.authorized_to(permiso, 'Subject') && materia &&
                   current_admin.schools_auh&.exists?(id: materia.school_id)
      return if autorizado

      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, alert: 'No autorizado' }
        format.json { render json: {error: 'No tiene permiso para cambiar prelaciones de esta escuela'}, status: :forbidden }
      end
    end
end
