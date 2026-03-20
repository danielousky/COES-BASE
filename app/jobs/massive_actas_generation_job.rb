class MassiveActasGenerationJob < ApplicationJob
  queue_as :default

  def perform(academic_process_id, user_id = nil)

    # p "     Iniciando proceso de actas masivas    ".center(300, "-")
    
    academic_process = AcademicProcess.find(academic_process_id)
    sections = academic_process.sections.qualified#.limit(1)
    

    # Crear un PDF combinado
    combined_pdf = CombinePDF.new
    
    # Generar PDFs y combinarlos usando la misma lógica que funciona en el controlador
    sections.each_with_index do |section, index|
      # p "     Procesando Acta sección #{section.name}    ".center(1000, "#")
      Rails.logger.info "Procesando sección #{index + 1} de #{sections.count}: #{section.id}"
      
      begin
          
        # Generar el PDF usando WickedPDF
        pdf_data = ExportarPdfPrawn.acta_seccion section.id #WickedPdf.new.pdf_from_string(pdf_html)
        # Verificar que el PDF se generó correctamente antes de combinarlo
        
        combined_pdf << CombinePDF.parse(pdf_data.render)
        # p "     Sección #{section.id} procesada correctamente    ".center(1000, "#")
        Rails.logger.info "Sección #{section.id} procesada y combinada exitosamente"

      rescue => e
        # p "<     Error: #{e}        >".center(500, 'X')
        Rails.logger.error "Error procesando sección #{section.id}: #{e.message}"

        # Enviar correo con el error
        if user_id
          user = User.find(user_id)
          UserMailer.general(user, "Hubo un error al generar el acta para la sección #{section.name} (ID: #{section.id}): #{e.message}").deliver_now
        end
      end
    end
    
    # Guardar el PDF final usando Active Storage
    filename = "actas_periodo_#{academic_process.name}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.pdf"
    
    # Crear un blob temporal para el PDF
    begin
      Rails.logger.info "Guardando archivo en S3"
      p "     Guardando archivo en S3    ".center(1000, "#")
      
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(combined_pdf.to_pdf),
        filename: filename,
        content_type: 'application/pdf'
      )
      Rails.logger.info "Archivo guardado en S3 exitosamente: #{blob.key}"
    rescue => e
      Rails.logger.error "Error guardando archivo en S3: #{e.message}"
      raise e
      # Enviar correo con el error
      if user_id
        user = User.find(user_id)
        UserMailer.general(user, "Hubo un error al guardar el archivo de actas en S3: #{e.message}").deliver_now
      end
    end
    
    # Notificar al usuario si se proporcionó
    if user_id
      user = User.find(user_id)
      
      # p "Enviando Correo" if UserMailer.actas_generation_complete(user, combined_pdf.to_pdf, filename).deliver_now
      p "Enviando Correo S3" if UserMailer.actas_generation_complete(user, blob, filename).deliver_now
    end
    
    p "Generación de actas completada: #{filename}"
    Rails.logger.info "Generación de actas completada: #{filename}"
  end
end