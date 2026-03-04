class ExportarPdfPrawn
	include Prawn::View

	def self.acta_seccion section_id
		# Variable Locales
		section = Section.find section_id

		pdf = Prawn::Document.new(top_margin: 215, bottom_margin: 100, page_size: 'LETTER', info: {Title: "Acta de Sección #{section.name_to_file}", Author: "COES-FHE", Subject: "Acta de Sección", Creator: "COES-FHE"})

		# inscripciones = section.inscripcionsectiones.sort_by{|h| h.estudiante.usuario.apellidos}
		# Inscripciones confirmadas en periodos
		inscripciones = section.academic_records.joins(:enroll_academic_process).confirmed.includes(student: :user).order('users.last_name ASC')
		
		pdf.repeat(:all, dynamic: true) do
			pdf.bounding_box([0, 680], :width => 540, :height => 215) do
				self.encabezado_central_con_logo pdf, section.academic_process
				self.tabla_descripcion_convocatoria pdf, section
				self.tabla_descripcion_section pdf, section
 				# pdf.transparent(0) { pdf.stroke_bounds }
			end
			# pdf.bounding_box([0, 20], :width => 540, :height => 90) do
			pdf.bounding_box([0, -10], :width => 540, :height => 90) do
				self.acta_firmas pdf, section
				# pdf.transparent(0) { pdf.stroke_bounds }
			end
		end

		self.insertar_tabla_convocados pdf, inscripciones, section.subject.as_absolute?

		options = {
			at: [pdf.bounds.right - 280, -80],
			inline_format: true,
			size: 7
		}

		pdf.number_pages "PÁGINA: <b> <page> / <total> </b>", options
		return pdf
	end	
	
	private

	def self.insertar_tabla_convocados pdf, inscripciones, absolute

		if absolute
			data = [["<b>N°</b>", "<b>CÉDULA DE IDENTIDAD</b>", "<b>APELLIDOS Y NOMBRES</b>", "<b>COD. PLAN</b>", "<b>CALIF. DESCR.</b>", "<b>TIPO</b>", "<b>CALIF. EN LETRAS</b>"]]
			column_widths = {1 => 60, 2 => 240, 4 => 55, 5 => 30, 6 => 123}
			filler_row = ["****", "**********", "*****************************************************", "******", "****", "****", "************"]
		else
			data = [["<b>N°</b>", "<b>CÉDULA DE IDENTIDAD</b>", "<b>APELLIDOS Y NOMBRES</b>", "<b>COD. PLAN</b>", "<b>CALIF. DESCR.</b>", "<b>TIPO</b>","<b>CALIF. NUM.</b>", "<b>CALIF. EN LETRAS</b>"]]
			column_widths = {1 => 60, 2 => 220, 5 => 30, 7 => 118}
			filler_row = ["****", "**********", "*****************************************************", "******", "****", "****", "****", "************"]
		end

		inscripciones.each_with_index do |ar, i|			
			if !ar.qualifications.any? or absolute
				if absolute
					data << [i + 1, ar.user.ci, ar.user&.reverse_name, ar.study_plan&.code, ar.desc_conv, ar.cal_alfa, ar.num_to_s]
				else
					data << [i + 1, ar.user.ci, ar.user&.reverse_name, ar.study_plan&.code, ar.desc_conv, ar.cal_alfa, ar.q_value_to_acta, ar.num_to_s]
				end
			else
				ar.qualifications.each do |q|
					data << [i + 1, ar.user.ci, ar.user&.reverse_name, ar.study_plan&.code, q.desc_conv, q.cal_alfa, q.value_to_acta, q.num_to_s]
					i += 1
				end
			end
		end

		cell_style = {
			:inline_format => true,
			:size => 8,
			align: :center,
			valign: :center,
			padding: 2,
			overflow: :shrink_to_fit,
			min_font_size: 6,
			border_color: '818284'
		}

		# Rellenar filas faltantes con asteriscos para completar la última página
		# Se calcula dinámicamente según el alto útil para evitar desajustes de paginación.
		header_row_height = 18
		data_row_height = 14
		filas_por_pagina = [((pdf.bounds.height - header_row_height) / data_row_height).floor, 1].max
		filas_datos = data.length - 1
		resto = filas_datos % filas_por_pagina
		filas_faltantes = (filas_por_pagina - resto) % filas_por_pagina

		filas_faltantes.times { data << filler_row.dup }

		pdf.table data do |t|
			t.width = 540
			t.position = :center
			t.header = true
			t.row_colors = ["F0F0F0", "FFFFFF"]
			t.column_widths = column_widths
			t.cell_style = cell_style
			
			t.column(2).style(:align => :left)
			t.row(0).style(:align => :center, :height => 18)
			t.rows(1..-1).style(:height => 14)
			# t.column(1).style(:font_style => :bold)
		end

	end


	def self.tabla_descripcion_convocatoria pdf, section
		# pdf.number_pages "<page> in a total of <total>", [bounds.right - 50, 0]
    	# pdf.start_page_numbering(, 9, nil, , 1)
		academic_process = section.academic_process
		data = [["FECHA DE LA EMISIÓN: <b>#{Time.now.strftime('%d/%m/%Y %I:%M %p')}</b>", "ACTA No.: <b>#{section.number_acta}</b>"]]
		data << ["EJERCICIO: <b>#{academic_process.process_name}</b>", "PERIODO ACADÉMICO: <b>#{academic_process.process_name}</b>" ]
		data << ["FACULTAD: <b>#{section.school&.faculty&.name}</b>", "TIPO DE CONVOCATORIA: <b>#{section.conv_type}</b>" ]
		if section.school.postgrado?

			code_plan = section.subject.code[0..3] if section.subject.code.present?
			if study_plan = StudyPlan.where(code: code_plan).first
				descripcion = study_plan.name.upcase
			else
				descripcion = section.subject.name.upcase
			end

			data << ["<b>#{descripcion}</b>", "" ]

		else
			data << ["ESCUELA: <b>#{section.school.name.upcase}</b>", "" ]
		end

		t = pdf.make_table(
			data,
			header: false,
			width: 540,
			position: :center,
			column_widths: {0 => 270, 1 => 270},
			cell_style: { inline_format: true, size: 9, padding: 1, border_color: 'FFFFFF'}
		)
		t.column(0).style(align: :left)
		t.column(1).style(align: :right)
		t.draw
	end
	
	def self.tabla_descripcion_section pdf, section

		pdf.move_down 3
		asig = section.subject

		data = [["<b>Código</b>", "<b>Asignatura</b>", "<b>Sección</b>", "<b>Tipo</b>", "<b>Créditos</b>", "<b>Duración</b>", "<b>T. Insc</b>"]]

		data << [ "#{asig.code}", "#{asig.name}", "#{section.code&.upcase}", "#{asig.modality_initial_letter}", "#{asig.unit_credits}", "#{section.conv_long}", "#{section.academic_records.confirmed.count}"]

		t = pdf.make_table(
			data,
			header: true,
			row_colors: ["F0F0F0", "FFFFFF"],
			width: 540,
			position: :center,
			column_widths: {0 => 55, 1 => 255, 2 => 40, 3 => 35, 4 => 45, 5 => 55, 6 => 55},
			cell_style: {
				inline_format: true,
				size: 9,
				align: :center,
				valign: :center,
				padding: 2,
				single_line: true,
				overflow: :shrink_to_fit,
				min_font_size: 6,
				border_color: '818284'
			}
		)
		t.row(0).style(height: 15)
		t.row(1).style(height: 15)
		t.draw
		pdf.move_down 4		
	end

	def self.acta_firmas pdf, section

		data = [["<b>JURADO EXAMINADOR</b>", "<b>SECRETARÍA</b>"]]
		t = pdf.make_table(data, header: false, width: 540, position: :center, cell_style: { inline_format: true, size: 9, align: :center, padding: 1, border_color: 'FFFFFF'}, :column_widths => {0 => 360})
		t.draw

		pdf.move_down 5

		prof_aux = section.teacher ? section.teacher&.user&.reverse_name&.upcase : "___________________________" 
		data = [["APELLIDOS Y NOMBRES", "FIRMAS", ""]]
		data << ["#{prof_aux}", "___________________________", "NOMBRE: _______________________"]
		data << ["___________________________", "___________________________", "FIRMA:     _______________________"]
		data << ["___________________________", "___________________________", "FECHA:    _______________________"]

		t = pdf.make_table(data, header: false, width: 540, position: :center, cell_style: { inline_format: true, size: 9, align: :center, padding: 1, border_color: 'FFFFFF'})
		t.draw

	end

	def self.encabezado_central_con_logo pdf, academic_process, size = nil, student = nil

		size = 9
		pdf.image "app/assets/images/logo_ucv.png", position: :center, height: 35, valign: :top
		pdf.move_down 2
		pdf.text "UNIVERSIDAD CENTRAL DE VENEZUELA", align: :center, size: size, style: :bold 
		pdf.move_down 2
		pdf.text "CONTROL DE ESTUDIOS #{academic_process&.school&.type_entity.upcase}", align: :center, size: size
		pdf.move_down 2
		pdf.text "PLANILLA DE EXÁMENES", align: :center, size: size, style: :bold
		pdf.move_down 2
		pdf.text "TIPO DE EXAMEN: #{academic_process.exame_type.upcase}", align: :center, size: size

		pdf.move_down 2

		# return pdf
	end


end