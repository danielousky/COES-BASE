class ValidarController < ApplicationController
  before_action :set_version, only: %i[ constancias ]
  skip_before_action :authenticate_user!, only: [ :constancias ]

  layout 'logged'
  def constancias

    if (@version and @version.item.is_a? EnrollAcademicProcess and (params[:study] and @version.event.eql? 'Se generó Constancia de Estudio') or (@version.event.eql? 'Se generó Constancia de Inscripción'))

      @study = params[:study] ? true : false

      flash[:success] = '¡Documento Válido!'
      @item = @version.item
      
    else
      flash[:danger] = 'Recurso no accesible. Puede que el documento no sea válido o halla sido alterado. Contacte a las autoridades para la validación del documento.'
      redirect_to root_path
    end

  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_version
      begin
        @enroll_academic_process = EnrollAcademicProcess.find (params[:object_id])

        # salt  = SecureRandom.random_bytes(32)
        # key   = ActiveSupport::KeyGenerator.new('password').generate_key(salt, 32) 
        # crypt = ActiveSupport::MessageEncryptor.new(key)
        
        # params[:id] = "#{params[:id]}/#{params[:salt]}" unless (params[:salt].blank?)

        # decrypted_id = crypt.decrypt_and_verify(params[:id])

        @version = @enroll_academic_process.versions.find(params[:id])
        
      rescue StandardError => e
        flash[:danger] = "Recurso no accesible. Puede que el documento no sea válido o halla sido alterado. Contacte a las autoridades para la validación del documento: #{e}"
        redirect_to root_path
      end
    end

end
