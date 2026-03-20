class ExportController < ApplicationController
  before_action :logged_as_admin?
  include Streamable

  def history_grade
    @grade = Grade.find params[:id]
    data = @grade.csv_academic_records
    title = "registro_academico_ #{@grade.short_name}"

    respond_to do |format|
      format.xls {send_data data, filename: "#{title}.xls"}
    end

  end


  def xls
    if params[:grades_others] and params[:id]
      academic_process = AcademicProcess.find params[:id]
      list = academic_process.invalid_grades_to_csv
      title = "No Validos para Cita Horaria #{academic_process.name}"
    end
    respond_to do |format|
      format.xls {send_data list, filename: "#{title}.xls"}
    end
  end

  def general
    # require 'xlsxtream'
    begin
      @object = AcademicProcess.find(params[:id])
      
      model = @object.class.name.underscore
      model_titulo = "#{I18n.t("activerecord.models.#{model}.one")&.titleize}"
      aux = "Reporte Coes - Registros - #{model_titulo} #{Time.current.strftime('%d-%m-%Y_%I:%M%P')}.csv"
      set_streaming_headers(aux)    


      # io = StringIO.new
      # xlsx = Xlsxtream::Workbook.new(io)
      
      # xlsx.add_worksheet(name: "Registros Académicos de #{model_titulo}") do |sheet|
      #   ActiveRecord::Base.connection.uncached do
      #     @object.academic_records.includes(:section, :user, :period, :subject, :area).find_each(batch_size: 500) do |academic_record|
      #       response.stream.write sheet.add_row(academic_record.valuse_for_report)
      #     end
      #   end
      # end

      response.stream.write %w{CI NOMBRES APELLIDOS ESCUELA CATEDRA ASIGNATURA PERIODO SECCIÓN ESTADO}.join(";")+"\n"
      @object.academic_records.includes(:section, :user, :subject, :area, :study_plan, :school, period: :period_type).find_each(batch_size: 500) do |academic_record|
        response.stream.write "#{academic_record.values_for_report.join(';')}\n"
      end

    rescue StandardError => e
      flash[:danger] = "No se pudo generar el archivo: #{e}" 
      redirect_back fallback_location: '/admin'
    ensure
      response.stream.close
    end
  end  

end
