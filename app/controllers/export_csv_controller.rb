class ExportCsvController < ApplicationController
  before_action :authenticate_user!
  before_action :validate_model_name, only: [:academic_records, :enroll_academic_processes]
  include ActionController::Live
  include Streamable

  ALLOWED_MODELS = %w[School AcademicProcess Period Subject Area Departament Section Course StudyPlan].freeze

  def stream
    response.headers['Content-Type'] = 'text/event-stream'
    5.times {
      response.stream.write "Hola Mundo\n"
      sleep 4
    }
  ensure
    response.stream.close
  end


  def academic_records
    # require 'xlsxtream'
    begin
      @object = params[:model_name].camelize.constantize.find(params[:id])

      model = @object.class.name.underscore
      model_titulo = "#{I18n.t("activerecord.models.#{model}.one")&.titleize}"
      aux = "Reporte Coes - Registros - #{model_titulo} #{Time.current.strftime('%d-%m-%Y_%I:%M%P')}.csv"
      set_streaming_headers(aux)

      a = AcademicRecord.header_for_report #['#', 'CI', 'NOMBRES', 'APELLIDOS', 'ESCUELA', 'CATEDRA','CÓDIGO ASIG', 'NOMBRE ASIG','PERIODO','SECCIÓN','ESTADO']
      
      @object.academic_records.includes(:section, :user, :period, :subject, :area).find_each(batch_size: 500).with_index do |academic_record, i|
        response.stream.write "#{a.join(';')}\n" if (i.eql? 0) 
        response.stream.write "#{i+1}; #{academic_record.values_for_report.join(';')}\n"
      end

      # Ojo: Versión incompleta con xlsx
      # io = StringIO.new
      # xlsx = Xlsxtream::Workbook.new(io)
      
      # xlsx.add_worksheet(name: "Registros Académicos de #{model_titulo}") do |sheet|
      #   ActiveRecord::Base.connection.uncached do
      #     @object.academic_records.includes(:section, :user, :period, :subject, :area).find_each(batch_size: 500) do |academic_record|
      #       response.stream.write sheet.add_row(academic_record.valuse_for_report)
      #     end
      #   end
      # end

    rescue StandardError => e
      flash[:danger] = "No se pudo generar el archivo: #{e}" 
      redirect_back fallback_location: '/admin'
    ensure
      response.stream.close
    end
  end

  def enroll_academic_processes
    begin
      @object = params[:model_name].camelize.constantize.find(params[:id])
      cod = @object.name
      cod ||= @object.code
      cod ||= @object.id
      model = @object.class.name.underscore
      model_titulo = "#{I18n.t("activerecord.models.#{model}.one")&.titleize}"
      aux = "Reporte Coes - Inscritos - #{model_titulo} #{cod} #{Time.current.strftime('%d-%m-%Y_%I:%M%P')}.csv"
      set_streaming_headers(aux)

      a = EnrollAcademicProcess.header_for_report #['#', 'CI', 'NOMBRES', 'APELLIDOS','ESCUELA','PERIODO','ESTADO INSCRIP','ESTADO PERMANENCIA','REPORTE PAGO']
      
      @object.enroll_academic_processes.includes(:user, :grade, :academic_process, :payment_reports).find_each(batch_size: 500).with_index do |enroll_academic_process, i|
        response.stream.write "#{a.join(';')}\n" if (i.eql? 0) 
        response.stream.write "#{i+1}; #{enroll_academic_process.values_for_report.join(';')}\n"
      end

    rescue StandardError => e
      flash[:danger] = "No se pudo generar el archivo: #{e}" 
      redirect_back fallback_location: '/admin'
    ensure
      response.stream.close
    end
  end


  private

  def validate_model_name
    model_name = params[:model_name].to_s.camelize
    unless ALLOWED_MODELS.include?(model_name)
      flash[:danger] = 'Modelo no permitido para exportación'
      redirect_back fallback_location: '/admin'
    end
  end
end